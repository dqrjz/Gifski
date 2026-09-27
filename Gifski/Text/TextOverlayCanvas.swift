import AppKit

/// Lives for the edit screen's lifetime, so updating SwiftUI bindings never interrupts an AppKit drag.
final class TextOverlayCanvas: NSView {
	override var isFlipped: Bool { true }
	override var mouseDownCanMoveWindow: Bool { false }
	private var overlays = [TextOverlay]()
	private var selectedID: UUID?
	private weak var session: TextEditingSession?
	private var overlay: TextOverlay { overlays.first { $0.id == selectedID } ?? TextOverlay() }
	private var outputSize = CGSize.zero
	private var crop = CropRect.initial
	private var editable = false
	private var rendered: TextOverlayRenderer.Layer?
	private var renderError: Swift.Error?
	private var startPoint = CGPoint.zero
	private var startOverlay: TextOverlay?
	private var isResizing = false
	private var startInkBounds: CGRect?
	private var wasClipped = false

	override func setFrameSize(_ newSize: CGSize) {
		super.setFrameSize(newSize)
		// Every pixel depends on the normalized crop and output size. AppKit's
		// partial resize invalidation would leave old crop shading in the interior.
		needsDisplay = true
		window?.invalidateCursorRects(for: self)
	}

	func update(session: TextEditingSession, outputSize: CGSize, crop: CropRect, editable: Bool, onClippingChange: @escaping (Bool) -> Void) {
		if self.overlays != session.overlays || self.outputSize != outputSize {
			do {
				rendered = try TextOverlayRenderer.render(session.overlays, width: max(1, Int(outputSize.width)), height: max(1, Int(outputSize.height)))
				renderError = nil
			} catch {
				rendered = nil
				renderError = error
			}
		}

		let canvasRect = CGRect(origin: .zero, size: outputSize)
		let isClipped = session.selectedID.flatMap { rendered?.bounds[$0] }.map { !canvasRect.contains($0) } ?? false
		if wasClipped != isClipped {
			wasClipped = isClipped
			DispatchQueue.main.async { onClippingChange(isClipped) }
		}
		self.overlays = session.overlays
		self.selectedID = session.selectedID
		self.session = session
		self.outputSize = outputSize
		self.crop = crop
		self.editable = editable
		needsDisplay = true
		window?.invalidateCursorRects(for: self)
	}

	private var cropFrame: CGRect {
		crop.unnormalize(forDimensions: bounds.size)
	}

	private var selection: CGRect {
		let canvas = cropFrame
		let ink = rendered?.bounds[overlay.id]
		let scale = canvas.size.height / max(1, outputSize.height)
		let height = max(28, (ink?.size.height ?? outputSize.height * overlay.normalizedFontSize) * scale)
		let width = canvas.size.width * overlay.normalizedBoxWidth
		let center = CGPoint(x: canvas.minX + overlay.normalizedCenter.x * canvas.size.width, y: canvas.minY + overlay.normalizedCenter.y * canvas.size.height)
		return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
	}

	private var resizeHandle: CGRect {
		CGRect(x: selection.maxX - 5, y: selection.midY - 9, width: 10, height: 18)
	}

	override func draw(_ dirtyRect: CGRect) {
		super.draw(dirtyRect)
		let shade = NSBezierPath(rect: bounds)
		shade.appendRect(cropFrame)
		shade.windingRule = .evenOdd
		NSColor.black.withAlphaComponent(0.5).setFill()
		shade.fill()
		if let image = rendered?.image {
			NSImage(cgImage: image, size: outputSize).draw(in: cropFrame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
		}

		guard editable, selectedID != nil else {
			return
		}

		NSColor.controlAccentColor.setStroke()
		let border = NSBezierPath(rect: selection.insetBy(dx: -3, dy: -3))
		border.lineWidth = 1
		border.stroke()
		NSColor.controlBackgroundColor.setFill()
		let handle = NSBezierPath(roundedRect: resizeHandle, xRadius: 3, yRadius: 3)
		handle.fill()
		handle.stroke()
		if renderError != nil {
			("Text is too large to render." as NSString).draw(at: CGPoint(x: 10, y: 10), withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12)])
		}
	}

	override func hitTest(_ point: CGPoint) -> NSView? {
		guard editable else {
			return nil
		}

		let local = convert(point, from: superview)
		return (selectedID != nil && selection.insetBy(dx: -8, dy: -8).contains(local)) || layer(at: local) != nil ? self : nil
	}

	private func layer(at point: CGPoint) -> UUID? {
		let canvas = cropFrame
		guard outputSize.width > 0, outputSize.height > 0 else {
			return nil
		}
		let outputPoint = CGPoint(x: (point.x - canvas.minX) / max(1, canvas.size.width) * outputSize.width, y: (point.y - canvas.minY) / max(1, canvas.size.height) * outputSize.height)
		return overlays.reversed().first { layer in
			rendered?.bounds[layer.id]?.insetBy(dx: -4, dy: -4).contains(outputPoint) ?? false
		}?.id
	}

	override var acceptsFirstResponder: Bool { true }
	override var undoManager: UndoManager? { session?.undoManager }

	override func mouseDown(with event: NSEvent) {
		startPoint = convert(event.locationInWindow, from: nil)
		isResizing = selectedID != nil && resizeHandle.insetBy(dx: -5, dy: -5).contains(startPoint)
		if !isResizing, let id = layer(at: startPoint) {
			session?.select(id)
			selectedID = id
		}
		guard let selected = session?.selectedOverlay else {
			return
		}
		window?.makeFirstResponder(self)
		startOverlay = selected
		startInkBounds = rendered?.bounds[selected.id]
		session?.beginContinuousChange(isResizing ? "Resize Text" : "Move Text")
	}

	override func mouseDragged(with event: NSEvent) {
		guard let startOverlay else {
			return
		}

		let point = convert(event.locationInWindow, from: nil)
		let canvas = cropFrame
		guard canvas.size.width > 0, canvas.size.height > 0 else {
			return
		}

		let changed = TextOverlayGeometry.dragged(
			startOverlay,
			translation: CGSize(width: point.x - startPoint.x, height: point.y - startPoint.y),
			displaySize: canvas.size,
			outputSize: outputSize,
			inkBounds: startInkBounds,
			resizing: isResizing
		)
		session?.update(changed)
	}

	override func mouseUp(with event: NSEvent) {
		startOverlay = nil
		session?.endContinuousChange()
	}

	override func resetCursorRects() {
		super.resetCursorRects()
		guard editable, selectedID != nil else {
			return
		}

		addCursorRect(selection, cursor: .openHand)
		addCursorRect(resizeHandle.insetBy(dx: -5, dy: -5), cursor: .resizeLeftRight)
	}
}
