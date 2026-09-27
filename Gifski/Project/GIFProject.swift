import AVFoundation
import CoreText
import CryptoKit
import Foundation

/// A reproducible recipe. Media stays external; trims use seconds, never frame indices.
struct GIFProject: Codable, Equatable {
	static let schemaVersion = 1
	static let rendererVersion = "gifski-text-project-1"
	var version = Self.schemaVersion
	var source: Source
	var settings: Settings
	var compatibility: Compatibility
	var expectedGIFSHA256: String?

	struct Source: Codable, Equatable {
		var originalFilename: String
		var sha256: String
		var metadata: Metadata
	}

	struct Metadata: Codable, Equatable {
		var width: Double
		var height: Double
		var duration: Double
		var frameRate: Double
		var fileSize: Int
		var hasAudio: Bool
		var transform: Transform?

		init(_ metadata: AVAsset.VideoMetadata) {
			width = metadata.dimensions.width
			height = metadata.dimensions.height
			duration = Double(metadata.duration.components.seconds) + Double(metadata.duration.components.attoseconds) / 1e18
			frameRate = metadata.frameRate
			fileSize = metadata.fileSize
			hasAudio = metadata.hasAudio
			transform = metadata.trackPreferredTransform.map(Transform.init)
		}
	}

	// swiftlint:disable identifier_name
	struct Transform: Codable, Equatable {
		var a: Double
		var b: Double
		var c: Double
		var d: Double
		var tx: Double
		var ty: Double
		init(_ value: CGAffineTransform) {
			a = value.a; b = value.b; c = value.c; d = value.d; tx = value.tx; ty = value.ty
		}
		var affineTransform: CGAffineTransform { .init(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }
		var isValid: Bool { [a, b, c, d, tx, ty].allSatisfy(\.isFinite) && abs(a * d - b * c) > 0.000001 }
	}

	// swiftlint:enable identifier_name
	struct TimeRange: Codable, Equatable {
		var start: Double
		var end: Double
		var range: ClosedRange<Double> { start...end }
	}

	struct Rect: Codable, Equatable {
		var x: Double
		var y: Double
		var width: Double
		var height: Double
		init(_ crop: CropRect) { x = crop.x; y = crop.y; width = crop.width; height = crop.height }
		var cropRect: CropRect { .init(x: x, y: y, width: width, height: height) }
	}

	enum Loop: Codable, Equatable {
		case never
		case forever
		case count(Int)
		init(_ loop: Gifski.Loop) {
			switch loop {
			case .never:
				self = .never
			case .forever:
				self = .forever
			case .count(let count):
				self = .count(count)
			}
		}
		var gifskiLoop: Gifski.Loop {
			switch self {
			case .never:
				.never
			case .forever:
				.forever
			case .count(let count):
				.count(count)
			}
		}
	}

	struct Settings: Codable, Equatable {
		var speed: Double
		/// Seconds on the original source timeline.
		var sourceTrim: TimeRange
		/// Seconds after applying speed; this is GIFGenerator.Conversion.timeRange.
		var adjustedTrim: TimeRange
		var width: Int
		var height: Int
		var frameRate: Int
		var quality: Double
		var loop: Loop
		var bounce: Bool
		var loopDelay: Double
		var crop: Rect?
		var trackPreferredTransform: Transform?
		var textOverlays: [TextOverlay]

		func conversion(asset: AVAsset, sourceURL: URL) -> GIFGenerator.Conversion {
			.init(asset: asset, sourceURL: sourceURL, timeRange: adjustedTrim.range, quality: quality, dimensions: (width, height), frameRate: frameRate, loop: loop.gifskiLoop, bounce: bounce, loopDelay: loopDelay, crop: crop?.cropRect, trackPreferredTransform: trackPreferredTransform?.affineTransform, textOverlays: textOverlays)
		}
	}

	struct Font: Codable, Equatable {
		var postScriptName: String
		var version: String
		var fileSHA256: String
	}

	struct Compatibility: Codable, Equatable {
		var renderer: String
		var appVersion: String
		var operatingSystem: String
		var fonts: [Font]
	}

	enum Error: LocalizedError {
		case incompatible(String)
		case invalid(String)
		var errorDescription: String? {
			switch self {
			case .incompatible(let reason):
				"This project cannot be reproduced: \(reason)"
			case .invalid(let reason):
				"Invalid GIF project: \(reason)"
			}
		}
	}

	// Optional means use the conversion layers; an explicit empty array is distinct.
	@MainActor
	// swiftlint:disable:next discouraged_optional_collection
	static func create(sourceURL: URL, metadata: AVAsset.VideoMetadata, conversion: GIFGenerator.Conversion, speed: Double, textOverlays: [TextOverlay]? = nil, expectedGIFSHA256: String? = nil) async throws -> Self {
		let sourceMetadata = Metadata(metadata)
		guard speed.isFinite, speed > 0, let dimensions = conversion.dimensions, let frameRate = conversion.frameRate else {
			throw Error.invalid("Output dimensions, frame rate, and speed must be explicit.")
		}
		guard sourceMetadata.duration.isFinite, sourceMetadata.duration > 0 else { throw Error.invalid("Invalid source duration.") }
		let trim = conversion.timeRange ?? (0...(sourceMetadata.duration / speed))
		let settings = Settings(speed: speed, sourceTrim: .init(start: trim.lowerBound * speed, end: trim.upperBound * speed), adjustedTrim: .init(start: trim.lowerBound, end: trim.upperBound), width: dimensions.width, height: dimensions.height, frameRate: frameRate, quality: conversion.quality, loop: Loop(conversion.loop), bounce: conversion.bounce, loopDelay: conversion.loopDelay, crop: conversion.crop.map(Rect.init), trackPreferredTransform: conversion.trackPreferredTransform.map(Transform.init), textOverlays: textOverlays ?? conversion.textOverlays)
		var project = Self(source: .init(originalFilename: sourceURL.lastPathComponent, sha256: "", metadata: sourceMetadata), settings: settings, compatibility: .init(renderer: rendererVersion, appVersion: appVersion, operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, fonts: []), expectedGIFSHA256: expectedGIFSHA256)
		project.source.sha256 = try await fileSHA256(sourceURL)
		project.compatibility.fonts = try await fonts(for: settings.textOverlays)
		try project.validateValues()
		return project
	}

	@MainActor
	func validate(sourceURL: URL, metadata: AVAsset.VideoMetadata) async throws {
		try validateValues()
		guard compatibility.renderer == Self.rendererVersion, compatibility.appVersion == Self.appVersion, compatibility.operatingSystem == ProcessInfo.processInfo.operatingSystemVersionString else {
			throw Error.incompatible("The application, renderer, or macOS version has changed.")
		}
		guard source.metadata == Metadata(metadata), try await Self.fileSHA256(sourceURL) == source.sha256 else {
			throw Error.incompatible("The selected video is different from the original source.")
		}
		guard try await Self.fonts(for: settings.textOverlays) == compatibility.fonts else {
			throw Error.incompatible("A required font is missing or has changed.")
		}
	}

	func encoded() throws -> Data {
		try validateValues()
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return try encoder.encode(self)
	}

	static func decode(_ data: Data) throws -> Self {
		guard data.count <= 16 * 1024 * 1024 else { throw Error.invalid("Project exceeds 16 MB.") }
		let project = try JSONDecoder().decode(Self.self, from: data)
		try project.validateValues()
		return project
	}

	static func sha256(of data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

	private static var appVersion: String {
		"\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"))"
	}

	private static func fileSHA256(_ url: URL) async throws -> String {
		try await Task.detached(priority: .userInitiated) {
			let file = try FileHandle(forReadingFrom: url)
			defer { try? file.close() }
			var hash = SHA256()
			while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty {
				try Task.checkCancellation()
				hash.update(data: data)
			}
			return hash.finalize().map { String(format: "%02x", $0) }.joined()
		}.value
	}

	@MainActor
	private static func fonts(for overlays: [TextOverlay]) async throws -> [Font] {
		var result = [Font]()
		var names = Set(overlays.map(\.fontPostScriptName))
		// Record actual fallback faces as well (for example Chinese or emoji
		// characters unavailable in the selected Latin face).
		for overlay in overlays {
			let base = CTFontCreateWithName(overlay.fontPostScriptName as CFString, 16, nil)
			let text = NSAttributedString(string: overlay.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): base])
			let line = CTLineCreateWithAttributedString(text)
			for run in CTLineGetGlyphRuns(line) as! [CTRun] {
				let attributes = CTRunGetAttributes(run) as NSDictionary
				if let font = attributes[kCTFontAttributeName] {
					names.insert(CTFontCopyPostScriptName(font as! CTFont) as String)
				}
			}
		}
		for name in names.sorted() {
			let font = CTFontCreateWithName(name as CFString, 16, nil)
			guard CTFontCopyPostScriptName(font) as String == name, let url = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL else {
				throw Error.incompatible("Required font “\(name)” is unavailable.")
			}
			result.append(.init(postScriptName: name, version: CTFontCopyName(font, kCTFontVersionNameKey) as String? ?? "", fileSHA256: try await fileSHA256(url)))
		}
		return result
	}

	private func validateValues() throws {
		guard version == Self.schemaVersion else { throw Error.incompatible("Unsupported project version \(version).") }
		func require(_ condition: Bool, _ message: String) throws { if !condition { throw Error.invalid(message) } }
		func isHash(_ value: String) -> Bool { value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) } }
		try require(isHash(source.sha256) && (expectedGIFSHA256.map(isHash) ?? true), "Invalid SHA-256.")
		let metadata = source.metadata
		try require([metadata.width, metadata.height, metadata.duration, metadata.frameRate].allSatisfy { $0.isFinite && $0 > 0 } && metadata.fileSize > 0, "Invalid video metadata.")
		try require(metadata.transform?.isValid ?? true, "Invalid source transform.")
		let value = settings
		try require(value.speed.isFinite && (0.5...5).contains(value.speed), "Invalid speed.")
		try require(value.width > 0 && value.height > 0 && value.width <= 32_768 && value.height <= 32_768 && value.width <= 67_108_864 / value.height, "Invalid dimensions.")
		try require((3...50).contains(value.frameRate) && value.quality.isFinite && (0.01...1).contains(value.quality), "Invalid frame rate or quality.")
		let maximumWidth = metadata.width * (value.crop?.width ?? 1)
		let maximumHeight = metadata.height * (value.crop?.height ?? 1)
		try require(Double(value.width) <= maximumWidth.rounded() && Double(value.height) <= maximumHeight.rounded(), "Output exceeds the cropped source dimensions.")
		try require(abs(Double(value.height) - Double(value.width) * maximumHeight / maximumWidth) <= 1, "Output aspect ratio differs from the crop.")
		try require(metadata.frameRate.effectiveFrameRateRange(speed: value.speed).contains(value.frameRate), "Frame rate exceeds the source rate at this speed.")
		try require(value.loopDelay.isFinite && (0...10).contains(value.loopDelay), "Invalid loop delay.")
		if case .count(let count) = value.loop { try require((1...100).contains(count), "Invalid loop count.") }
		let trim = value.adjustedTrim
		try require([trim.start, trim.end, value.sourceTrim.start, value.sourceTrim.end].allSatisfy(\.isFinite) && trim.start >= 0 && trim.end > trim.start && trim.end * value.speed <= metadata.duration + 0.001, "Invalid trim range.")
		try require(abs(trim.start * value.speed - value.sourceTrim.start) < 0.000001 && abs(trim.end * value.speed - value.sourceTrim.end) < 0.000001, "Conflicting trim timelines.")
		try require(value.trackPreferredTransform?.isValid ?? true, "Invalid output transform.")
		if let crop = value.crop {
			try require([crop.x, crop.y, crop.width, crop.height].allSatisfy(\.isFinite) && crop.x >= 0 && crop.y >= 0 && crop.width > 0 && crop.height > 0 && crop.x + crop.width <= 1.000001 && crop.y + crop.height <= 1.000001, "Invalid crop.")
		}
		try require(value.textOverlays.count <= 100 && Set(value.textOverlays.map(\.id)).count == value.textOverlays.count, "Invalid text layers.")
		for text in value.textOverlays {
			try require(text.text.utf16.count <= 100_000 && !text.fontPostScriptName.isEmpty, "Invalid text content or font.")
			try require([text.normalizedCenter.x, text.normalizedCenter.y, text.normalizedBoxWidth, text.normalizedFontSize, text.normalizedStrokeWidth].allSatisfy(\.isFinite) && (0...1).contains(text.normalizedCenter.x) && (0...1).contains(text.normalizedCenter.y) && (0.1...1).contains(text.normalizedBoxWidth) && text.normalizedFontSize > 0 && text.normalizedFontSize <= 1 && text.normalizedStrokeWidth >= 0 && text.normalizedStrokeWidth <= 1, "Invalid text layout.")
			for color in [text.fillRGBA, text.strokeRGBA] {
				try require([color.red, color.green, color.blue, color.alpha].allSatisfy { $0.isFinite && (0...1).contains($0) }, "Invalid text color.")
			}
		}
		try require(Set(value.textOverlays.map(\.fontPostScriptName)).isSubset(of: Set(compatibility.fonts.map(\.postScriptName))) && compatibility.fonts.map(\.postScriptName) == Set(compatibility.fonts.map(\.postScriptName)).sorted() && compatibility.fonts.allSatisfy { isHash($0.fileSHA256) }, "Invalid font fingerprints.")
	}
}
