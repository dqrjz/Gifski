import AppKit
import Testing
@testable import Gifski

@MainActor
struct TextEditingSessionTests {
	private func edit(_ session: TextEditingSession, _ action: () -> Void) {
		session.undoManager.beginUndoGrouping()
		action()
		session.undoManager.endUndoGrouping()
	}

	private func makeSession() -> TextEditingSession {
		let session = TextEditingSession()
		session.begin()
		session.undoManager.removeAllActions()
		session.undoManager.groupsByEvent = false
		return session
	}

	@Test
	func continuousChangesUndoAsOneActionAndRedo() throws {
		let session = makeSession()
		let original = try #require(session.selectedOverlay)
		edit(session) {
			session.beginContinuousChange("Move Text")
			for step in 1...10 {
				var changed = original
				changed.normalizedCenter.x = Double(step) / 10
				session.update(changed)
			}
			session.endContinuousChange()
		}
		#expect(session.selectedOverlay?.normalizedCenter.x == 1)
		session.undo()
		#expect(session.selectedOverlay == original)
		#expect(!session.canUndo)
		session.redo()
		#expect(session.selectedOverlay?.normalizedCenter.x == 1)
	}

	@Test
	func addDeleteMaintainOrderAndCancellationIsIdempotent() throws {
		let suite = "Gifski.TextSessionTests.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		let preferences = TextStylePreferences(defaults: defaults)
		let session = TextEditingSession(preferences: preferences)
		session.begin()
		session.finish(cancelled: false)
		session.undoManager.groupsByEvent = false
		let before = session.overlays
		let priorStyle = preferences.load().overlay
		session.begin()
		edit(session) { session.add() }
		#expect(session.overlays.count == 2)
		#expect(session.selectedID == session.overlays.last?.id)
		edit(session) { session.deleteSelected() }
		#expect(session.overlays == before)
		session.undo()
		#expect(session.overlays.count == 2)
		session.finish(cancelled: true)
		#expect(session.overlays == before)
		session.finish(cancelled: false)
		#expect(TextOverlayStyle(preferences.load().overlay) == TextOverlayStyle(priorStyle))
	}

	@Test
	func nativeTextUndoSurvivesLayerSelectionAndDeletion() throws {
		let session = makeSession()
		defer { session.finish(cancelled: true) }
		let first = try #require(session.selectedOverlay)
		let firstEditor = try #require(session.editors.view(for: first).documentView as? NSTextView)
		edit(session) { firstEditor.insertText("甲", replacementRange: NSRange(location: (firstEditor.string as NSString).length, length: 0)) }
		#expect(session.overlays[0].text == "文字甲")
		edit(session) { session.add() }
		let second = try #require(session.selectedOverlay)
		let secondEditor = try #require(session.editors.view(for: second).documentView as? NSTextView)
		edit(session) { secondEditor.insertText("乙", replacementRange: NSRange(location: (secondEditor.string as NSString).length, length: 0)) }
		#expect(session.overlays[1].text == "文字乙")
		session.select(first.id)
		session.undo()
		#expect(session.overlays[1].text == "文字")
		#expect(session.selectedID == second.id)
		session.select(first.id)
		session.select(second.id)
		// Mimic a SwiftUI refresh after changing the picker, then redo the native edit.
		session.editors.synchronize(session.overlays)
		session.redo()
		#expect(session.overlays[1].text == "文字乙")
		#expect(session.selectedID == second.id)
		session.undo()
		session.undo()
		#expect(session.overlays.count == 1)
		session.undo()
		#expect(session.overlays[0].text == "文字")
		session.redo()
		#expect(session.overlays[0].text == "文字甲")
	}

	@Test
	func synchronizationDoesNotReplaceMarkedChineseInput() throws {
		let session = makeSession()
		defer { session.finish(cancelled: true) }
		let overlay = try #require(session.selectedOverlay)
		let editor = try #require(session.editors.view(for: overlay).documentView as? NSTextView)
		edit(session) {
			editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
		}
		#expect(editor.hasMarkedText())
		var modelRefresh = overlay
		modelRefresh.text = "should not replace marked text"
		session.editors.synchronize([modelRefresh])
		#expect(editor.string == "ni")
		#expect(editor.hasMarkedText())
		edit(session) { editor.insertText("你", replacementRange: editor.markedRange()) }
		#expect(!editor.hasMarkedText())
		#expect(session.selectedOverlay?.text == "你")
	}

	@Test
	func savedStyleContainsNoContentPositionOrIdentityAndMissingFontFallsBack() throws {
		let suite = "Gifski.TextStyleTests.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		let preferences = TextStylePreferences(defaults: defaults)
		var overlay = TextOverlay(text: "PRIVATE CONTENT", fontPostScriptName: "Font-That-Does-Not-Exist")
		overlay.normalizedCenter = .init(x: 0.2, y: 0.3)
		overlay.normalizedStrokeWidth = 0.025
		preferences.save(overlay)
		let loaded = preferences.load()
		#expect(loaded.overlay.text.isEmpty)
		#expect(loaded.overlay.id != overlay.id)
		#expect(loaded.overlay.normalizedCenter == TextOverlay().normalizedCenter)
		#expect(loaded.overlay.normalizedStrokeWidth == overlay.normalizedStrokeWidth)
		#expect(loaded.missingFont)
		#expect(loaded.overlay.fontPostScriptName == TextOverlay().fontPostScriptName)
		let data = try #require(defaults.data(forKey: "textOverlayStyle-v1"))
		let json = try #require(String(data: data, encoding: .utf8))
		#expect(!json.contains("PRIVATE CONTENT"))
		#expect(!json.contains("normalizedCenter"))
	}
}
