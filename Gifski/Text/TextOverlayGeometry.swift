import CoreGraphics

/// Translates view-space drags into the final cropped output's normalized coordinates.
enum TextOverlayGeometry {
	static func dragged(
		_ overlay: TextOverlay,
		translation: CGSize,
		displaySize: CGSize,
		outputSize: CGSize,
		inkBounds: CGRect?,
		resizing: Bool
	) -> TextOverlay {
		guard displaySize.width > 0, displaySize.height > 0, outputSize.width > 0, outputSize.height > 0 else {
			return overlay
		}

		var result = overlay
		if resizing {
			// The center stays fixed: moving the right handle grows both sides equally.
			result.normalizedBoxWidth = min(1, max(0.1, overlay.normalizedBoxWidth + translation.width * 2 / displaySize.width))
			return result
		}

		var deltaX = translation.width / displaySize.width
		var deltaY = translation.height / displaySize.height
		if let ink = inkBounds {
			if ink.size.width <= outputSize.width {
				deltaX = min((outputSize.width - ink.maxX) / outputSize.width, max(-ink.minX / outputSize.width, deltaX))
			}
			if ink.size.height <= outputSize.height {
				deltaY = min((outputSize.height - ink.maxY) / outputSize.height, max(-ink.minY / outputSize.height, deltaY))
			}
		}

		result.normalizedCenter.x = min(1, max(0, overlay.normalizedCenter.x + deltaX))
		result.normalizedCenter.y = min(1, max(0, overlay.normalizedCenter.y + deltaY))
		return result
	}
}
