import AppKit
import CoreText

@MainActor
enum SystemFontCatalog {
	struct Face: Identifiable {
		let id: String
		let name: String
	}

	static let families = NSFontManager.shared.availableFontFamilies.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

	static func family(for name: String) -> String {
		NSFont(name: name, size: 24)?.familyName ?? "PingFang SC"
	}

	static func faces(in family: String) -> [Face] {
		(NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { member in
			guard let name = member.first as? String, let style = member.dropFirst().first as? String else {
				return nil
			}

			return Face(id: name, name: style)
		}
	}

	/// Check Chinese characters separately: Latin-only fonts commonly fall back without an obvious font change.
	static func needsChineseFallback(_ overlay: TextOverlay) -> Bool {
		let characters = overlay.text.utf16.filter { (0x3400...0x9FFF).contains($0) || (0xF900...0xFAFF).contains($0) }
		guard !characters.isEmpty else {
			return false
		}

		let font = CTFontCreateWithName(overlay.fontPostScriptName as CFString, 24, nil)
		var glyphs = [CGGlyph](repeating: 0, count: characters.count)
		return !CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
	}
}

extension TextOverlay.RGBA {
	var nsColor: NSColor {
		NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
	}

	init(_ color: NSColor) {
		let color = color.usingColorSpace(.sRGB) ?? .white
		self.init(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent, alpha: color.alphaComponent)
	}
}
