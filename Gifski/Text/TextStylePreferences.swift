import AppKit

/// Only reusable presentation settings are persisted — never content, identity, or position.
struct TextOverlayStyle: Codable, Equatable {
	var fontPostScriptName: String
	var normalizedBoxWidth: Double
	var normalizedFontSize: Double
	var normalizedStrokeWidth: Double
	var fillRGBA: TextOverlay.RGBA
	var strokeRGBA: TextOverlay.RGBA
	var alignment: TextOverlay.Alignment

	init(_ overlay: TextOverlay) {
		fontPostScriptName = overlay.fontPostScriptName
		normalizedBoxWidth = overlay.normalizedBoxWidth
		normalizedFontSize = overlay.normalizedFontSize
		normalizedStrokeWidth = overlay.normalizedStrokeWidth
		fillRGBA = overlay.fillRGBA
		strokeRGBA = overlay.strokeRGBA
		alignment = overlay.alignment
	}

	func makeOverlay() -> TextOverlay {
		TextOverlay(fontPostScriptName: fontPostScriptName, normalizedBoxWidth: normalizedBoxWidth, normalizedFontSize: normalizedFontSize, normalizedStrokeWidth: normalizedStrokeWidth, fillRGBA: fillRGBA, strokeRGBA: strokeRGBA, alignment: alignment)
	}
}

@MainActor
struct TextStylePreferences {
	private let defaults: UserDefaults
	private let key = "textOverlayStyle-v1"

	init(defaults: UserDefaults = .standard) { self.defaults = defaults }

	func save(_ overlay: TextOverlay) {
		guard let data = try? JSONEncoder().encode(TextOverlayStyle(overlay)) else {
			return
		}
		defaults.set(data, forKey: key)
	}

	func load() -> (overlay: TextOverlay, missingFont: Bool) {
		guard let data = defaults.data(forKey: key), let style = try? JSONDecoder().decode(TextOverlayStyle.self, from: data) else {
			return (TextOverlay(), false)
		}
		var overlay = style.makeOverlay()
		// Preferences may come from another app version. Invalid numeric values do not reach render/UI controls.
		overlay.normalizedBoxWidth = valid(overlay.normalizedBoxWidth, in: 0.1...1, fallback: 0.9)
		overlay.normalizedFontSize = valid(overlay.normalizedFontSize, in: 0.001...1, fallback: 0.09)
		overlay.normalizedStrokeWidth = valid(overlay.normalizedStrokeWidth, in: 0...0.1, fallback: 0.012)
		let missing = NSFont(name: overlay.fontPostScriptName, size: 24) == nil
		if missing { overlay.fontPostScriptName = TextOverlay().fontPostScriptName }
		return (overlay, missing)
	}

	private func valid(_ value: Double, in range: ClosedRange<Double>, fallback: Double) -> Double {
		value.isFinite && range.contains(value) ? value : fallback
	}
}
