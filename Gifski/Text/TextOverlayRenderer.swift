import AppKit
import CoreText

/// Stateless rendering; cache the returned layer per conversion and reuse it for every frame.
enum TextOverlayRenderer {
	enum Error: LocalizedError {
		case invalidCanvas
		case invalidOverlay
		case allocationFailed
		case mismatchedCanvas

		var errorDescription: String? {
			switch self {
			case .invalidCanvas:
				"The output is too large for text overlays. Reduce the GIF dimensions."
			case .invalidOverlay:
				"The text is too large to render. Reduce its length, size, or outline width."
			case .allocationFailed:
				"There is not enough memory to render the text. Reduce the GIF dimensions."
			case .mismatchedCanvas:
				"The text canvas does not match the video frame dimensions."
			}
		}
	}

	struct Layer {
		let image: CGImage
		/// Unclipped bounds in top-left output coordinates, including glyph overhang and stroke.
		let bounds: [UUID: CGRect]
	}

	static func render(_ overlays: [TextOverlay], width: Int, height: Int) throws -> Layer? {
		// Bound a single RGBA layer to 256 MiB before asking Core Graphics to allocate.
		guard width > 0, height > 0, width <= 32_768, height <= 32_768, width <= 67_108_864 / height else {
			throw Error.invalidCanvas
		}

		let visibleOverlays = overlays.filter(\.hasVisibleText)
		guard !visibleOverlays.isEmpty else {
			return nil
		}

		let context = try makeContext(width: width, height: height)
		var bounds = [UUID: CGRect]()
		for overlay in visibleOverlays {
			bounds[overlay.id] = try draw(overlay, in: context, canvas: CGSize(width: width, height: height))
		}

		guard let image = context.makeImage() else {
			throw Error.allocationFailed
		}

		return Layer(image: image, bounds: bounds)
	}

	/// A nil layer returns the original image without allocating or copying pixels.
	static func composite(_ layer: Layer?, onto image: CGImage) throws -> CGImage {
		guard let layer else {
			return image
		}

		guard layer.image.width == image.width, layer.image.height == image.height else {
			throw Error.mismatchedCanvas
		}

		let context = try makeContext(width: image.width, height: image.height)
		let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
		context.draw(image, in: rect)
		context.draw(layer.image, in: rect)
		guard let result = context.makeImage() else {
			throw Error.allocationFailed
		}

		return result
	}

	private static func makeContext(width: Int, height: Int) throws -> CGContext {
		guard let context = CGContext(
			data: nil,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: 0,
			space: CGColorSpace(name: CGColorSpace.sRGB)!,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		) else {
			throw Error.allocationFailed
		}

		return context
	}

	private static func draw(_ overlay: TextOverlay, in context: CGContext, canvas: CGSize) throws -> CGRect {
		let numbers = [overlay.normalizedCenter.x, overlay.normalizedCenter.y, overlay.normalizedBoxWidth, overlay.normalizedFontSize, overlay.normalizedStrokeWidth]
		guard numbers.allSatisfy(\.isFinite), overlay.normalizedBoxWidth > 0, overlay.normalizedFontSize > 0, overlay.normalizedStrokeWidth >= 0 else {
			throw Error.invalidOverlay
		}

		let fontSize = overlay.normalizedFontSize * canvas.height
		let strokeWidth = overlay.normalizedStrokeWidth * canvas.height
		let boxWidth = overlay.normalizedBoxWidth * canvas.width
		guard fontSize.isFinite, fontSize <= 4096, strokeWidth.isFinite, strokeWidth <= 4096, boxWidth.isFinite, boxWidth <= 65_536,
			overlay.text.utf16.count <= 100_000,
			abs(overlay.normalizedCenter.x) <= 100,
			abs(overlay.normalizedCenter.y) <= 100
		else {
			throw Error.invalidOverlay
		}

		let font = CTFontCreateWithName(overlay.fontPostScriptName as CFString, fontSize, nil)
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = switch overlay.alignment {
		case .left:
			.left
		case .center:
			.center
		case .right:
			.right
		}
		paragraph.lineBreakMode = .byWordWrapping
		let attributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: color(overlay.fillRGBA),
			.paragraphStyle: paragraph
		]
		let text = NSAttributedString(string: overlay.text, attributes: attributes)
		let framesetter = CTFramesetterCreateWithAttributedString(text)
		let size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil, CGSize(width: boxWidth, height: .greatestFiniteMagnitude), nil)
		guard size.height.isFinite, size.height <= 65_536 else {
			throw Error.invalidOverlay
		}

		let boxHeight = ceil(size.height) + 1
		let origin = CGPoint(x: overlay.normalizedCenter.x * canvas.width - boxWidth / 2, y: (1 - overlay.normalizedCenter.y) * canvas.height - boxHeight / 2)
		let path = CGPath(rect: CGRect(x: 0, y: 0, width: boxWidth, height: boxHeight), transform: nil)
		let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)

		context.saveGState()
		defer { context.restoreGState() }
		context.translateBy(x: origin.x, y: origin.y)
		context.textMatrix = .identity

		if strokeWidth > 0 {
			let outlined = NSMutableAttributedString(attributedString: text)
			outlined.addAttributes([
				.strokeColor: color(overlay.strokeRGBA),
				.strokeWidth: strokeWidth / fontSize * 100
			], range: NSRange(location: 0, length: outlined.length))
			let strokeFrame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(outlined), CFRange(), path, nil)
			context.setLineJoin(.round)
			CTFrameDraw(strokeFrame, context)
		}

		CTFrameDraw(frame, context)
		let lines = CTFrameGetLines(frame) as! [CTLine]
		var origins = [CGPoint](repeating: .zero, count: lines.count)
		CTFrameGetLineOrigins(frame, CFRange(), &origins)
		var inkBounds = CGRect.null
		for (line, lineOrigin) in zip(lines, origins) {
			let lineBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
			inkBounds = inkBounds.union(lineBounds.offsetBy(dx: lineOrigin.x, dy: lineOrigin.y))
		}

		if inkBounds.isNull {
			inkBounds = CGRect(x: 0, y: 0, width: boxWidth, height: boxHeight)
		}

		let padded = inkBounds.insetBy(dx: -strokeWidth / 2 - 1, dy: -strokeWidth / 2 - 1).offsetBy(dx: origin.x, dy: origin.y)
		return CGRect(x: padded.minX, y: canvas.height - padded.maxY, width: padded.width, height: padded.height)
	}

	private static func color(_ rgba: TextOverlay.RGBA) -> NSColor {
		func component(_ value: Double) -> Double {
			value.isFinite ? min(1, max(0, value)) : 0
		}

		return NSColor(srgbRed: component(rgba.red), green: component(rgba.green), blue: component(rgba.blue), alpha: component(rgba.alpha))
	}
}
