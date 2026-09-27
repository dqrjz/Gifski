import AppKit
import AVFoundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Gifski

struct TextOverlayTests {
	private func pixels(_ image: CGImage) throws -> [UInt8] {
		let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
		context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
		let data = try #require(context.data)
		return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
	}

	@Test
	@MainActor
	func checkerboardUsesHostCoordinatesAndUpdatedHeight() {
		let video = CGRect(x: 30, y: 50, width: 240, height: 240)
		let host = CGRect(x: 10, y: 20, width: 300, height: 400)
		#expect(TrimmingAVPlayerView.checkerboardClearRect(video, in: host, isFlipped: true) == CGRect(x: 20, y: 30, width: 240, height: 240))
		#expect(TrimmingAVPlayerView.checkerboardClearRect(video, in: host, isFlipped: false) == CGRect(x: 20, y: 130, width: 240, height: 240))
		let grownHost = CGRect(x: 10, y: 20, width: 300, height: 470)
		#expect(TrimmingAVPlayerView.checkerboardClearRect(video, in: grownHost, isFlipped: false).minY == 200)
	}

	@Test
	@MainActor
	func canvasResizeInvalidatesEntireCropMaskAfterInspectorCloses() {
		let canvas = TextOverlayCanvas(frame: CGRect(x: 0, y: 0, width: 480, height: 270))
		canvas.needsDisplay = false
		// Closing the taller inspector grows the player without changing the
		// model. The old interior crop shading must be repainted as well.
		canvas.setFrameSize(CGSize(width: 560, height: 315))
		#expect(canvas.needsToDraw(canvas.bounds))
		#expect(canvas.needsToDraw(CGRect(x: 100, y: 200, width: 50, height: 20)))
		canvas.needsDisplay = false
		canvas.setFrameSize(CGSize(width: 480, height: 270))
		#expect(canvas.needsToDraw(canvas.bounds))
	}

	@Test
	func fullPreviewSnapshotIncludesTextAndInvalidatesCache() {
		let url = URL(filePath: "/dev/null")
		var conversion = GIFGenerator.Conversion(asset: AVURLAsset(url: url), sourceURL: url, loop: .never, bounce: false)
		let original = SettingsForFullPreview(conversion: conversion, speed: 1, frameRate: 20, assetDuration: .seconds(2))
		conversion.textOverlays = [TextOverlay(text: "快照测试")]
		let updated = SettingsForFullPreview(conversion: conversion, speed: 1, frameRate: 20, assetDuration: .seconds(2))
		#expect(original != updated)
		#expect(updated.conversion.toConversion(asset: conversion.asset, frameRate: 20).textOverlays == conversion.textOverlays)
		#expect(original.areSettingsDifferentEnoughForANewFullPreview(newSettings: updated, areCurrentlyGenerating: false, oldRequestID: 1, newRequestID: 2))
	}

	@Test
	func draggingUsesCroppedDisplayScaleAndClampsInk() {
		let overlay = TextOverlay(text: "拖动", normalizedCenter: .init(x: 0.5, y: 0.5))
		let output = CGSize(width: 640, height: 360)
		let ink = CGRect(x: 200, y: 150, width: 240, height: 60)
		let moved = TextOverlayGeometry.dragged(overlay, translation: CGSize(width: 32, height: 18), displaySize: CGSize(width: 320, height: 180), outputSize: output, inkBounds: ink, resizing: false)
		#expect(abs(moved.normalizedCenter.x - 0.6) < 0.001)
		#expect(abs(moved.normalizedCenter.y - 0.6) < 0.001)
		let larger = TextOverlayGeometry.dragged(overlay, translation: CGSize(width: 64, height: 36), displaySize: output, outputSize: output, inkBounds: ink, resizing: false)
		#expect(larger.normalizedCenter == moved.normalizedCenter)
		let bottomRight = TextOverlayGeometry.dragged(overlay, translation: CGSize(width: 1000, height: 1000), displaySize: output, outputSize: output, inkBounds: ink, resizing: false)
		#expect(abs((bottomRight.normalizedCenter.x - 0.5) * 640 + ink.maxX - 640) < 0.001)
		#expect(abs((bottomRight.normalizedCenter.y - 0.5) * 360 + ink.maxY - 360) < 0.001)
		let topLeft = TextOverlayGeometry.dragged(overlay, translation: CGSize(width: -1000, height: -1000), displaySize: output, outputSize: output, inkBounds: ink, resizing: false)
		#expect(abs((topLeft.normalizedCenter.x - 0.5) * 640 + ink.minX) < 0.001)
		#expect(abs((topLeft.normalizedCenter.y - 0.5) * 360 + ink.minY) < 0.001)
	}

	@Test
	func resizingPreservesCenterAndLimitsWidth() {
		let overlay = TextOverlay(text: "宽度", normalizedBoxWidth: 0.5)
		let size = CGSize(width: 640, height: 360)
		let wider = TextOverlayGeometry.dragged(overlay, translation: CGSize(width: 64, height: 0), displaySize: size, outputSize: size, inkBounds: nil, resizing: true)
		#expect(abs(wider.normalizedBoxWidth - 0.7) < 0.001)
		#expect(wider.normalizedCenter == overlay.normalizedCenter)
		let narrower = TextOverlayGeometry.dragged(overlay, translation: CGSize(width: -1000, height: 0), displaySize: size, outputSize: size, inkBounds: nil, resizing: true)
		#expect(narrower.normalizedBoxWidth == 0.1)
		#expect(TextOverlayGeometry.dragged(overlay, translation: size, displaySize: .zero, outputSize: size, inkBounds: nil, resizing: false) == overlay)
	}

	@Test
	func colorPickerComponentsRoundTrip() {
		let original = TextOverlay.RGBA(red: 0.2, green: 0.65, blue: 0.9, alpha: 0.4)
		let restored = TextOverlay.RGBA(original.nsColor)
		#expect(abs(restored.red - original.red) < 0.00001)
		#expect(abs(restored.green - original.green) < 0.00001)
		#expect(abs(restored.blue - original.blue) < 0.00001)
		#expect(abs(restored.alpha - original.alpha) < 0.00001)
	}

	@Test
	func renderingRejectsUnsafeDimensionsAndMismatchedComposition() throws {
		let overlay = TextOverlay(text: "尺寸")
		for size in [(0, 1), (-1, 10), (Int.max, 1), (1, Int.max), (32_768, 32_768)] {
			#expect(throws: TextOverlayRenderer.Error.invalidCanvas) {
				try TextOverlayRenderer.render([overlay], width: size.0, height: size.1)
			}
		}
		let small = try #require(try TextOverlayRenderer.render([overlay], width: 320, height: 180))
		let larger = try #require(try TextOverlayRenderer.render([overlay], width: 640, height: 360))
		#expect(throws: TextOverlayRenderer.Error.mismatchedCanvas) {
			try TextOverlayRenderer.composite(small, onto: larger.image)
		}
		var invalid = overlay
		invalid.normalizedFontSize = Double.greatestFiniteMagnitude
		#expect(throws: TextOverlayRenderer.Error.invalidOverlay) {
			try TextOverlayRenderer.render([invalid], width: 320, height: 180)
		}
	}

	@Test
	func laterTextLayerDrawsOnTop() throws {
		var red = TextOverlay(text: "叠放", normalizedCenter: .init(x: 0.5, y: 0.5), normalizedFontSize: 0.3, normalizedStrokeWidth: 0)
		red.fillRGBA = .init(red: 1, green: 0, blue: 0)
		var blue = red
		blue.id = UUID()
		blue.fillRGBA = .init(red: 0, green: 0, blue: 1)
		let blueOnTop = try #require(try TextOverlayRenderer.render([red, blue], width: 320, height: 180))
		let redOnTop = try #require(try TextOverlayRenderer.render([blue, red], width: 320, height: 180))
		let bluePixels = try pixels(blueOnTop.image)
		let redPixels = try pixels(redOnTop.image)
		#expect(stride(from: 0, to: bluePixels.count, by: 4).filter { bluePixels[$0] < 30 && bluePixels[$0 + 2] > 230 }.count > 100)
		#expect(stride(from: 0, to: redPixels.count, by: 4).filter { redPixels[$0] > 230 && redPixels[$0 + 2] < 30 }.count > 100)
	}

	@Test
	func valueSnapshotRoundTrips() throws {
		var overlay = TextOverlay()
		overlay.text = "你好，GIF！\n系统中文字体"
		let snapshot = try JSONDecoder().decode(TextOverlay.self, from: JSONEncoder().encode(overlay))
		#expect(snapshot == overlay)
		var changed = snapshot
		changed.normalizedStrokeWidth = 0
		#expect(changed != overlay)
	}

	@Test
	func emptyOverlayDoesNotAllocateOrCopy() throws {
		#expect(try TextOverlayRenderer.render([TextOverlay(text: " \n")], width: 320, height: 240) == nil)
		let layer = try #require(try TextOverlayRenderer.render([TextOverlay(text: "字")], width: 320, height: 240))
		#expect(try TextOverlayRenderer.composite(nil, onto: layer.image) === layer.image)
	}

	@Test(arguments: ["PingFangSC-Semibold", "STSongti-SC-Regular"])
	func chineseOutlineExpandsInkAndPreservesTransparentCanvas(font: String) throws {
		#expect(NSFont(name: font, size: 24) != nil)
		var overlay = TextOverlay(text: "中文描边，Hello 123", fontPostScriptName: font)
		overlay.normalizedCenter = .init(x: 0.5, y: 0.25)
		let outlined = try #require(try TextOverlayRenderer.render([overlay], width: 400, height: 300))
		overlay.normalizedStrokeWidth = 0
		let plain = try #require(try TextOverlayRenderer.render([overlay], width: 400, height: 300))
		let outlinePixels = try pixels(outlined.image)
		let plainPixels = try pixels(plain.image)
		let alphas = stride(from: 3, to: outlinePixels.count, by: 4)
		#expect(alphas.filter { outlinePixels[$0] > 0 }.count > alphas.filter { plainPixels[$0] > 0 }.count)
		#expect(outlinePixels[3] == 0)
		let bounds = try #require(outlined.bounds[overlay.id])
		#expect(bounds.midY < 150)
		#expect(bounds.size.width > plain.bounds[overlay.id]!.size.width)
		// Pixel rows from a bitmap image use top-left coordinates; all visible pixels must match the reported bounds.
		for index in stride(from: 0, to: outlinePixels.count, by: 4) where outlinePixels[index + 3] > 0 {
			let point = CGPoint(x: (index / 4) % 400, y: (index / 4) / 400)
			#expect(bounds.insetBy(dx: -1, dy: -1).contains(point))
		}
	}

	@Test
	func normalizedLayoutScalesAndRejectsInvalidInput() throws {
		let overlay = TextOverlay(text: "多行中文\n第二行")
		let small = try #require(try TextOverlayRenderer.render([overlay], width: 320, height: 240))
		let large = try #require(try TextOverlayRenderer.render([overlay], width: 640, height: 480))
		#expect(abs(large.bounds[overlay.id]!.midX - small.bounds[overlay.id]!.midX * 2) < 2)
		#expect(abs(large.bounds[overlay.id]!.size.height - small.bounds[overlay.id]!.size.height * 2) < 4)
		#expect(throws: TextOverlayRenderer.Error.invalidCanvas) {
			try TextOverlayRenderer.render([overlay], width: 0, height: 240)
		}
		var invalid = overlay
		invalid.normalizedFontSize = .nan
		#expect(throws: TextOverlayRenderer.Error.invalidOverlay) {
			try TextOverlayRenderer.render([invalid], width: 320, height: 240)
		}
	}

	@Test
	func compositedChineseFramesEncodeWithGifski() throws {
		let width = 480
		let height = 320
		let overlay = TextOverlay(text: "你好，GIF！\n中文描边 · Hello 123", normalizedCenter: .init(x: 0.5, y: 0.7))
		let layer = try #require(try TextOverlayRenderer.render([overlay], width: width, height: height))
		let encoder = try Gifski(quality: 1, loop: .forever)
		let directory = FileManager.default.temporaryDirectory.appending(path: "gifski-text-overlay-stage-a", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		for index in 0..<3 {
			let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
			context.setFillColor(CGColor(red: 0.15, green: 0.3, blue: 0.6, alpha: 1))
			context.fill(CGRect(x: 0, y: 0, width: width, height: height))
			context.setFillColor(CGColor(red: 0.95, green: 0.5, blue: 0.1, alpha: 1))
			context.fill(CGRect(x: 20 + index * 100, y: 220, width: 60, height: 60))
			let source = try #require(context.makeImage())
			let result = try TextOverlayRenderer.composite(layer, onto: source)
			#expect(try pixels(result)[3] == 255)
			try encoder.addFrame(result, presentationTimestamp: Double(index) * 0.2)
			if index == 0 {
				let destination = try #require(CGImageDestinationCreateWithURL(directory.appending(path: "chinese-composite.png") as CFURL, UTType.png.identifier as CFString, 1, nil))
				CGImageDestinationAddImage(destination, result, nil)
				#expect(CGImageDestinationFinalize(destination))
			}
		}
		let data = try encoder.finish()
		try data.write(to: directory.appending(path: "chinese-animation.gif"))
		let decoded = try #require(CGImageSourceCreateWithData(data as CFData, nil))
		#expect(CGImageSourceGetCount(decoded) == 3)
		let properties = try #require(CGImageSourceCopyProperties(decoded, nil) as? [String: Any])
		let gif = try #require(properties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
		#expect(gif[kCGImagePropertyGIFLoopCount as String] as? Int == 0)
		let frame = try #require(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
		let output = try pixels(frame)
		// The blue source contains no white pixels: these come from the encoded text fill.
		#expect(stride(from: 0, to: output.count, by: 4).filter { output[$0] > 230 && output[$0 + 1] > 230 && output[$0 + 2] > 230 }.count > 100)
	}
}
