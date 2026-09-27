import AppKit
import Observation

/// Editing history is local to one video and cleared at the session boundary.
@MainActor
@Observable
final class TextEditingSession {
	struct Snapshot: Equatable {
		var overlays: [TextOverlay]
		var selectedID: UUID?
	}

	private(set) var overlays = [TextOverlay]()
	var selectedID: UUID?
	private(set) var historyVersion = 0
	private(set) var missingSavedFont = false
	let undoManager = UndoManager()
	@ObservationIgnored private var savedSnapshot: Snapshot?
	@ObservationIgnored private var transactionStart: Snapshot?
	@ObservationIgnored private var transactionName = "Edit Text"
	@ObservationIgnored private let preferences: TextStylePreferences
	@ObservationIgnored lazy var editors = TextEditorPool(session: self)

	init(preferences: TextStylePreferences? = nil) {
		self.preferences = preferences ?? TextStylePreferences()
	}

	var selectedOverlay: TextOverlay? {
		overlays.first { $0.id == selectedID }
	}

	var visibleOverlays: [TextOverlay] {
		overlays.filter(\.hasVisibleText)
	}

	var canUndo: Bool {
		_ = historyVersion
		return undoManager.canUndo
	}

	var canRedo: Bool {
		_ = historyVersion
		return undoManager.canRedo
	}

	private var snapshot: Snapshot {
		Snapshot(overlays: overlays, selectedID: selectedID)
	}

	func loadProjectOverlays(_ layers: [TextOverlay]) {
		editors.clear()
		savedSnapshot = nil
		transactionStart = nil
		overlays = layers
		selectedID = layers.first?.id
		undoManager.removeAllActions()
		historyVersion += 1
	}

	func begin() {
		missingSavedFont = false
		savedSnapshot = snapshot
		undoManager.removeAllActions()
		historyVersion += 1
		if overlays.isEmpty {
			add()
		}
		if selectedOverlay == nil {
			selectedID = overlays.last?.id
		}
	}

	func finish(cancelled: Bool) {
		guard savedSnapshot != nil else {
			return
		}
		editors.commitMarkedText()
		endContinuousChange()
		if cancelled, let savedSnapshot {
			overlays = savedSnapshot.overlays
			selectedID = savedSnapshot.selectedID
		} else if let selectedOverlay {
			preferences.save(selectedOverlay)
		}
		savedSnapshot = nil
		undoManager.removeAllActions()
		editors.clear()
		historyVersion += 1
	}

	func add() {
		prepareDiscreteChange()
		let before = snapshot
		var overlay: TextOverlay
		if let selectedOverlay {
			overlay = TextOverlayStyle(selectedOverlay).makeOverlay()
		} else {
			let loaded = preferences.load()
			overlay = loaded.overlay
			missingSavedFont = loaded.missingFont
		}
		overlay.text = "文字"
		// Offset additional layers so a new one does not entirely hide the selected one.
		overlay.normalizedCenter.y = max(0.15, 0.85 - Double(overlays.count % 5) * 0.13)
		overlays.append(overlay)
		selectedID = overlay.id
		record(before, action: "Add Text")
	}

	func deleteSelected() {
		guard let selectedID else {
			return
		}
		prepareDiscreteChange()
		let before = snapshot
		overlays.removeAll { $0.id == selectedID }
		self.selectedID = overlays.last?.id
		record(before, action: "Delete Text")
	}

	func select(_ id: UUID?) {
		guard selectedID != id else {
			return
		}
		prepareDiscreteChange()
		selectedID = id
	}

	/// Native NSTextView owns text coalescing/IME undo. Do not record a second snapshot for typing.
	func updateText(_ text: String, id: UUID) {
		guard let index = overlays.firstIndex(where: { $0.id == id }) else {
			return
		}
		overlays[index].text = text
		if undoManager.isUndoing || undoManager.isRedoing {
			selectedID = id
		}
		historyVersion += 1
	}

	func update(_ overlay: TextOverlay, action: String = "Edit Text") {
		guard let index = overlays.firstIndex(where: { $0.id == overlay.id }), overlays[index] != overlay else {
			return
		}
		let before = snapshot
		if overlays[index].fontPostScriptName != overlay.fontPostScriptName { missingSavedFont = false }
		if transactionStart == nil { editors.breakUndoCoalescing() }
		overlays[index] = overlay
		if transactionStart == nil { record(before, action: action) }
	}

	func beginContinuousChange(_ name: String) {
		guard transactionStart == nil else {
			return
		}
		editors.commitMarkedText()
		editors.breakUndoCoalescing()
		transactionStart = snapshot
		transactionName = name
	}

	func endContinuousChange() {
		guard let before = transactionStart else {
			return
		}
		transactionStart = nil
		record(before, action: transactionName)
	}

	func undo() {
		prepareDiscreteChange()
		undoManager.undo()
		synchronizeNativeHistoryChange()
		historyVersion += 1
	}

	func redo() {
		prepareDiscreteChange()
		undoManager.redo()
		synchronizeNativeHistoryChange()
		historyVersion += 1
	}

	private func synchronizeNativeHistoryChange() {
		for change in editors.changedContents(comparedTo: overlays) {
			updateText(change.text, id: change.id)
			selectedID = change.id
		}
	}

	private func prepareDiscreteChange() {
		editors.commitMarkedText()
		editors.breakUndoCoalescing()
		endContinuousChange()
	}

	private func record(_ before: Snapshot, action: String) {
		guard before != snapshot else {
			return
		}
		undoManager.registerUndo(withTarget: self) { target in target.restore(before, action: action) }
		undoManager.setActionName(action)
		historyVersion += 1
	}

	private func restore(_ value: Snapshot, action: String) {
		let inverse = snapshot
		overlays = value.overlays
		selectedID = value.selectedID
		// Update retained editors too, including a layer that is not currently visible.
		editors.synchronize(overlays)
		undoManager.registerUndo(withTarget: self) { target in target.restore(inverse, action: action) }
		undoManager.setActionName(action)
		historyVersion += 1
	}
}
