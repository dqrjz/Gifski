import Foundation

/// A static text layer in the final, cropped output canvas. Coordinates start at the top left.
struct TextOverlay: Hashable, Codable, Sendable, Identifiable {
	struct Point: Hashable, Codable, Sendable {
		var x: Double
		var y: Double
	}

	struct RGBA: Hashable, Codable, Sendable {
		var red: Double
		var green: Double
		var blue: Double
		var alpha: Double = 1

		static let white = Self(red: 1, green: 1, blue: 1)
		static let black = Self(red: 0, green: 0, blue: 0)
	}

	enum Alignment: String, Codable, Sendable {
		case left
		case center
		case right
	}

	var id = UUID()
	var text = ""
	/// A concrete face also represents the font's actual weight and style.
	var fontPostScriptName = "PingFangSC-Semibold"
	var normalizedCenter = Point(x: 0.5, y: 0.85)
	var normalizedBoxWidth = 0.9
	/// Font size and total stroke width are fractions of canvas height.
	var normalizedFontSize = 0.09
	var normalizedStrokeWidth = 0.012
	var fillRGBA = RGBA.white
	var strokeRGBA = RGBA.black
	var alignment = Alignment.center

	var hasVisibleText: Bool {
		!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}
}
