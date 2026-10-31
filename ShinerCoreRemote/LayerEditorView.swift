import SwiftUI
import ShinerCoreKit

/// Edits one layer of the stack through the layer cursor, which Play has moved to `slot`.
struct LayerEditorView: View {
    let session: CoreSession
    let slot: Int
    /// The bottom layer, which blends onto black.
    let isBase: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let state = session.state
        let animation = state[CoreProps.animation]
        let doc = animation.map(state.animationDoc(for:)) ?? .generic
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Animation")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                        ForEach((state.documentation?.animations ?? []).dropFirst(), id: \.self) { name in
                            AnimationCard(name: name, state: state, selected: name == animation) {
                                session.set(CoreProps.animation, to: name)
                            }
                        }
                    }
                    .availability(of: CoreProps.animation, in: session)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Colors")
                    HStack(spacing: 20) {
                        Swatch(title: "Primary", session: session, key: CoreProps.color, used: doc.colors >= 1)
                        Button {
                            guard let primary = state.rawValue(of: CoreProps.color),
                                  let secondary = state.rawValue(of: CoreProps.color2) else { return }
                            session.set(CoreProps.color, to: ColorConverter.convert(secondary) ?? .black)
                            session.set(CoreProps.color2, to: ColorConverter.convert(primary) ?? .black)
                        } label: {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.headline)
                                .frame(width: 44, height: 44)
                        }
                        .disabled(doc.colors < 2)
                        .accessibilityLabel("Swap colors")
                        Swatch(title: "Secondary", session: session, key: CoreProps.color2, used: doc.colors >= 2)
                    }
                    .frame(maxWidth: .infinity)
                    if let animation, let note = SingleLayerView.colorNote(animation: animation, colors: doc.colors) {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Motion")
                    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            SpeedTile(session: session)
                            SettingTile("Beat sync", symbol: "waveform") {
                                Toggle("Beat sync", isOn: session.boolBinding(CoreProps.beatSync))
                                    .labelsHidden()
                            }
                            .availability(of: CoreProps.beatSync, in: session)
                        }
                        // Full width: parameter names such as "Counter-wave length" need the room.
                        if let tau = doc.tau {
                            GridRow {
                                ParameterTile(title: tau, session: session, key: CoreProps.tau).gridCellColumns(2)
                            }
                        }
                        if let phi = doc.phi {
                            GridRow {
                                ParameterTile(title: phi, session: session, key: CoreProps.phi).gridCellColumns(2)
                            }
                        }
                    }
                }

                // The base layer blends onto black, where every mode but a few looks like Add;
                // it still shows when another mode has been moved to the bottom.
                if !isBase || (state[CoreProps.blendMode].map { $0 != "Add" } ?? false) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Blend")
                        SettingTile("Mix with the layers below", symbol: "square.stack.3d.down.right") {
                            VocabularyPicker("Blend mode", session: session, key: CoreProps.blendMode,
                                             options: state.documentation?.blendModes ?? [])
                                .labelsHidden()
                        }
                        .availability(of: CoreProps.blendMode, in: session)
                    }
                }

                Button(role: .destructive) {
                    session.removeLayer(slot)
                    dismiss()
                } label: {
                    Text("Remove layer")
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.groupedSurface, in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
            .padding()
        }
        // Pinned, so the effect of a change shows while the controls below the fold are in reach.
        .safeAreaInset(edge: .top, spacing: 0) {
            LayerPreview(state: state)
                .frame(height: 84)  // the strip grows to fill whatever height it is offered
                .padding([.horizontal, .top])
                .padding(.bottom, 8)
                .background(Color.groupedBackground)
        }
        .background(Color.groupedBackground)
        .navigationTitle(isBase ? "Base layer" : "Layer \(slot)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

struct SectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

/// One animation to pick, previewed in the layer's own colors and parameters.
struct AnimationCard: View {
    let name: String
    let state: CoreState
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                StripPreview(looks: look.map { [$0] } ?? [], pixelCount: pixelCount,
                             caption: look == nil || RenderLibrary.animationDoc(named: name) == nil ? "" : nil,
                             compact: true)
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.18) : Color.groupedSurface, in: .rect(cornerRadius: 12))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 2) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var look: LayerLook? {
        guard var look = state.layerLook else { return nil }
        look.animation = name
        look.blendMode = "Set"
        return look
    }

    private var pixelCount: Int {
        let count = state[CoreProps.ledCount] ?? 0
        return count > 0 ? count : 60
    }
}

/// A big round swatch that opens the system color picker. Dimmed while the animation
/// ignores the color, but still editable: other animations use it.
struct Swatch: View {
    let title: String
    let session: CoreSession
    let key: PropertyKey<ColorConverter>
    var used = true

    var body: some View {
        let color = session.binding(key, default: .black)
        let known = session.state[key] != nil
        VStack(spacing: 8) {
            ZStack {
                // The stretched native well takes the taps; absent until loaded, as dimming would show its ring through the swatch.
                if known {
                    ColorPicker(title, selection: color, supportsOpacity: false)
                        .labelsHidden()
                        .scaleEffect(72 / 24)
                }
                Circle()
                    .fill(known ? color.wrappedValue : Color.secondary.opacity(0.15))
                    .strokeBorder(.secondary.opacity(0.3))
                    .allowsHitTesting(false)
            }
            .frame(width: 72, height: 72)
            .clipShape(.circle)
            .shadow(color: known && used ? color.wrappedValue.opacity(0.5) : .clear, radius: 12)
            .overlay {
                // A veil rather than opacity, which would let the stretched well show through.
                if !used {
                    Circle().fill(Color.groupedBackground.opacity(0.6)).allowsHitTesting(false)
                }
            }
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .availability(of: key, in: session)
    }
}

#Preview("Layer editor") {
    let link = FakeCoreLink.demo()
    link.values[CoreProps.layer.id] = "1"
    let session = CoreSession(link: link)
    return NavigationStack {
        LayerEditorView(session: session, slot: 1, isBase: false)
    }
    .task { await session.run() }
}

#Preview("Base layer") {
    let session = CoreSession(link: FakeCoreLink.demo())
    NavigationStack {
        LayerEditorView(session: session, slot: 0, isBase: true)
    }
    .task { await session.run() }
}
