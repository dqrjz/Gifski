import SwiftUI

/// Retains a native editor per layer so native undo still targets the right text after selection changes.
@MainActor
final class TextEditorPool {
	private weak var session: TextEditingSession?
	private var entries = [UUID: Entry]()

	init(session: TextEditingSession) { self.session = session }

	func view(for overlay: TextOverlay) -> NSScrollView {
		if let existing = entries[overlay.id] {
			return existing.scrollView
		}
		let entry = Entry(overlay: overlay, session: session)
		entries[overlay.id] = entry
		return entry.scrollView
	}

	func synchronize(_ overlays: [TextOverlay]) {
		for overlay in overlays {
			guard let editor = entries[overlay.id]?.textView, !editor.hasMarkedText(), editor.string != overlay.text else { continue }
			let range = editor.selectedRange()
			editor.string = overlay.text
			editor.setSelectedRange(NSRange(location: min(range.location, (overlay.text as NSString).length), length: 0))
		}
	}

	/// NSUndoManager can mutate a non-focused NSTextView without its textDidChange notification.
	/// Read the native storage before SwiftUI has a chance to refresh it from the model.
	func changedContents(comparedTo overlays: [TextOverlay]) -> [(id: UUID, text: String)] {
		overlays.compactMap { overlay in
			guard let editor = entries[overlay.id]?.textView, editor.string != overlay.text else {
				return nil
			}
			return (overlay.id, editor.string)
		}
	}

	func commitMarkedText() {
		for entry in entries.values where entry.textView.hasMarkedText() { entry.textView.unmarkText() }
	}

	func breakUndoCoalescing() {
		for entry in entries.values { entry.textView.breakUndoCoalescing() }
	}

	func clear() { entries.removeAll() }

	@MainActor
	private final class Entry: NSObject, NSTextViewDelegate {
		let scrollView = NSScrollView()
		let textView = SessionTextView()
		let id: UUID
		weak var session: TextEditingSession?

		init(overlay: TextOverlay, session: TextEditingSession?) {
			self.id = overlay.id
			self.session = session
			super.init()
			textView.sessionUndoManager = session?.undoManager
			textView.delegate = self
			textView.isRichText = false
			textView.allowsUndo = true
			textView.isAutomaticQuoteSubstitutionEnabled = false
			textView.isAutomaticDashSubstitutionEnabled = false
			textView.font = .systemFont(ofSize: NSFont.systemFontSize)
			textView.textColor = .textColor
			textView.backgroundColor = .textBackgroundColor
			textView.textContainerInset = CGSize(width: 5, height: 5)
			textView.isVerticallyResizable = true
			textView.isHorizontallyResizable = false
			textView.autoresizingMask = [.width]
			textView.textContainer?.widthTracksTextView = true
			textView.textContainer?.containerSize = CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
			textView.string = overlay.text
			textView.setAccessibilityLabel("Text content")
			scrollView.hasVerticalScroller = true
			scrollView.autohidesScrollers = true
			scrollView.borderType = .noBorder
			scrollView.documentView = textView
		}

		func textDidChange(_ notification: Notification) {
			session?.updateText(textView.string, id: id)
		}
	}

	private final class SessionTextView: NSTextView {
		weak var sessionUndoManager: UndoManager?
		override var undoManager: UndoManager? { sessionUndoManager }
	}
}

struct TextOverlayTextEditor: NSViewRepresentable {
	let overlay: TextOverlay
	let pool: TextEditorPool

	func makeNSView(context: Context) -> NSScrollView { pool.view(for: overlay) }

	func updateNSView(_ view: NSScrollView, context: Context) {
		pool.synchronize([overlay])
	}
}
