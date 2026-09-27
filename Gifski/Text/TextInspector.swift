import SwiftUI

/// Replaces the conversion settings while editing text, keeping the editor's existing two-column density.
struct TextInspector: View {
	@Bindable var session: TextEditingSession
	@Binding var overlay: TextOverlay
	let outputHeight: Double
	var isClipped = false

	private var fontFamily: Binding<String> {
		Binding(
			get: { SystemFontCatalog.family(for: overlay.fontPostScriptName) },
			set: { family in
				if let face = SystemFontCatalog.faces(in: family).first {
					overlay.fontPostScriptName = face.id
				}
			}
		)
	}

	private func color(_ keyPath: WritableKeyPath<TextOverlay, TextOverlay.RGBA>) -> Binding<Color> {
		Binding(get: { Color(nsColor: overlay[keyPath: keyPath].nsColor) }, set: { overlay[keyPath: keyPath] = .init(NSColor($0)) })
	}

	private func pixels(_ keyPath: WritableKeyPath<TextOverlay, Double>, limits: ClosedRange<Double>) -> Binding<Double> {
		Binding(get: { overlay[keyPath: keyPath] * outputHeight }, set: {
			guard $0.isFinite else {
				return
			}

			overlay[keyPath: keyPath] = min(limits.upperBound, max(limits.lowerBound, $0)) / max(1, outputHeight)
		})
	}

	private func continuous(_ name: String) -> (Bool) -> Void {
		{ editing in
			if editing { session.beginContinuousChange(name) } else { session.endContinuousChange() }
		}
	}

	var body: some View {
		HStack(alignment: .top, spacing: 20) {
			VStack(alignment: .leading, spacing: 10) {
				TextOverlayTextEditor(overlay: overlay, pool: session.editors)
					.id(overlay.id)
					.background(.background, in: RoundedRectangle(cornerRadius: 6))
					.overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
					.frame(height: 64)
					.accessibilityLabel("Text content")
				Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
					GridRow {
						VStack(alignment: .leading, spacing: 1) {
							Text("Font")
							Text("中文 Aa").font(.custom(overlay.fontPostScriptName, size: 10)).foregroundStyle(.secondary)
						}
						Picker("Font", selection: fontFamily) {
							ForEach(SystemFontCatalog.families, id: \.self) { Text($0).tag($0) }
						}
						.labelsHidden()
					}
					GridRow {
						Text("Style")
						Picker("Style", selection: $overlay.fontPostScriptName) {
							ForEach(SystemFontCatalog.faces(in: fontFamily.wrappedValue)) { Text($0.name).tag($0.id) }
						}
						.labelsHidden()
					}
					GridRow {
						Text("Align")
						Picker("Alignment", selection: $overlay.alignment) {
							Image(systemName: "text.alignleft").tag(TextOverlay.Alignment.left)
							Image(systemName: "text.aligncenter").tag(TextOverlay.Alignment.center)
							Image(systemName: "text.alignright").tag(TextOverlay.Alignment.right)
						}
						.pickerStyle(.segmented)
						.labelsHidden()
					}
				}
			}
			.frame(maxWidth: .infinity)
			Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
				GridRow {
					Text("Size")
					HStack {
						Slider(value: pixels(\.normalizedFontSize, limits: 4...max(4, min(4096, outputHeight))), in: 4...max(4, min(4096, outputHeight)), onEditingChanged: continuous("Change Text Size"))
						TextField("Size in pixels", value: pixels(\.normalizedFontSize, limits: 4...max(4, min(4096, outputHeight))), format: .number.precision(.fractionLength(0)))
							.frame(width: 46)
						Text("px").foregroundStyle(.secondary)
					}
				}
				GridRow {
					Text("Color")
					ColorPicker("Text color", selection: color(\.fillRGBA), supportsOpacity: false).labelsHidden()
				}
				GridRow {
					Text("Outline")
					HStack {
						ColorPicker("Outline color", selection: color(\.strokeRGBA), supportsOpacity: false).labelsHidden()
						Slider(value: pixels(\.normalizedStrokeWidth, limits: 0...max(1, outputHeight * 0.1)), in: 0...max(1, outputHeight * 0.1), onEditingChanged: continuous("Change Text Outline"))
						TextField("Outline width in pixels", value: pixels(\.normalizedStrokeWidth, limits: 0...max(1, outputHeight * 0.1)), format: .number.precision(.fractionLength(1)))
							.frame(width: 46)
						Text("px").foregroundStyle(.secondary)
					}
				}
				GridRow {
					Text("Width")
					Slider(value: $overlay.normalizedBoxWidth, in: 0.1...1, onEditingChanged: continuous("Resize Text")).accessibilityLabel("Text box width")
				}
				GridRow {
					Text("Position")
					HStack {
						Text("X").foregroundStyle(.secondary)
						Slider(value: $overlay.normalizedCenter.x, in: 0...1, onEditingChanged: continuous("Move Text")).accessibilityLabel("Horizontal position")
						Text("Y").foregroundStyle(.secondary)
						Slider(value: $overlay.normalizedCenter.y, in: 0...1, onEditingChanged: continuous("Move Text")).accessibilityLabel("Vertical position")
					}
				}
			}
			.textFieldStyle(.roundedBorder)
			.frame(maxWidth: .infinity)
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 6)
		.safeAreaInset(edge: .bottom, alignment: .leading, spacing: 0) {
			VStack(alignment: .leading, spacing: 2) {
				if isClipped {
					Label("Text extends beyond the GIF. Move it or reduce the size.", systemImage: "exclamationmark.triangle")
				}
				if session.missingSavedFont {
					Text("The previous font is unavailable. Using PingFang SC.")
				}
				if SystemFontCatalog.needsChineseFallback(overlay) {
					Text("Chinese characters use a fallback font.")
				}
			}
			.font(.caption)
			.foregroundStyle(.secondary)
			.padding(.horizontal, 8)
		}
	}
}
