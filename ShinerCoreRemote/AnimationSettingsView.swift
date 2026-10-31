import SwiftUI
import ShinerCoreKit

/// Everything that shapes the current animation, per preset and layer.
struct AnimationSettingsView: View {
    let session: CoreSession

    var body: some View {
        let docs = session.state.documentation
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PresetPicker(session: session)
                LayerPicker(session: session)
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        AnimationTile(session: session, options: docs?.animations ?? [])
                            .gridCellColumns(2)
                    }
                    GridRow {
                        ColorTile(title: "Primary", session: session, key: CoreProps.color)
                        ColorTile(title: "Secondary", session: session, key: CoreProps.color2)
                    }
                    GridRow {
                        SpeedTile(session: session)
                        SettingTile("Beat sync", symbol: "waveform") {
                            Toggle("Beat sync", isOn: session.boolBinding(CoreProps.beatSync))
                                .labelsHidden()
                        }
                        .availability(of: CoreProps.beatSync, in: session)
                    }
                    GridRow {
                        ParameterTile(title: "Tau", session: session, key: CoreProps.tau)
                        ParameterTile(title: "Phi", session: session, key: CoreProps.phi)
                    }
                    GridRow {
                        SettingTile("Blend mode", symbol: "square.stack.3d.down.right") {
                            VocabularyPicker("Blend mode", session: session, key: CoreProps.blendMode,
                                             options: docs?.blendModes ?? [])
                                .labelsHidden()
                        }
                        .gridCellColumns(2)
                        .availability(of: CoreProps.blendMode, in: session)
                    }
                }
            }
            .padding()
        }
        .background(Color.groupedBackground)
    }
}

/// Switches the whole core to another preset; disabled while a switch holds one.
struct PresetPicker: View {
    let session: CoreSession

    var body: some View {
        let heldBy = session.state.presetHold?.pin
        VStack(alignment: .leading, spacing: 6) {
            Picker("Preset", selection: Binding(
                get: { session.state[CoreProps.preset] ?? 0 },
                set: { session.select(CoreProps.preset, $0) }
            )) {
                ForEach(0 ..< CoreProps.presetCount, id: \.self) { Text("Preset \($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(heldBy != nil)
            HeldCaption(pin: heldBy)
        }
        .availability(of: CoreProps.preset, in: session)
    }
}

/// Points the per-layer tiles at one of the preset's layers.
struct LayerPicker: View {
    let session: CoreSession

    var body: some View {
        let selected = session.state[CoreProps.layer]
        VStack(alignment: .leading, spacing: 6) {
            Text("Layer")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(0 ..< CoreProps.layerCount, id: \.self) { layer in
                    let isSelected = layer == selected
                    Button { session.select(CoreProps.layer, layer) } label: {
                        Text("\(layer)")
                            .font(.body.monospacedDigit().weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.groupedSurface,
                                        in: .rect(cornerRadius: 10))
                            .overlay {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 1.5)
                                }
                            }
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Layer \(layer)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .availability(of: CoreProps.layer, in: session)
    }
}

/// The layer's animation: pick from the menu, or step through with − and +.
struct AnimationTile: View {
    let session: CoreSession
    let options: [String]
    private let key = CoreProps.animation

    var body: some View {
        let current = session.state[key]
        let index = current.flatMap(options.firstIndex(of:))
        SettingTile("Animation", symbol: "sparkles") {
            HStack {
                Menu {
                    VocabularyPicker("Animation", session: session, key: key, options: options)
                        .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 6) {
                        Text(current ?? "…")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                    }
                }
                Spacer(minLength: 8)
                Stepper("Animation",
                        onIncrement: step(from: index, by: 1),
                        onDecrement: step(from: index, by: -1))
                    .labelsHidden()
                    .accessibilityValue(current ?? "")
            }
        }
        .availability(of: key, in: session)
    }

    /// Nil past either end of the list, which disables that half of the stepper.
    private func step(from index: Int?, by delta: Int) -> (() -> Void)? {
        guard let index, options.indices.contains(index + delta) else { return nil }
        return { session.set(key, to: options[index + delta]) }
    }
}

struct ColorTile: View {
    let title: String
    let session: CoreSession
    let key: PropertyKey<ColorConverter>

    var body: some View {
        SettingTile(title, symbol: "paintpalette") {
            ColorPicker(title, selection: session.binding(key, default: .black))
                .labelsHidden()
        }
        .availability(of: key, in: session)
    }
}

/// Seconds per cycle, or beats per cycle while beat-synced.
struct SpeedTile: View {
    let session: CoreSession
    private let key = CoreProps.speed

    var body: some View {
        let speed = session.state[key]
        let beatSynced = (session.state[CoreProps.beatSync] ?? 0) > 0
        let value = speed.map { beatSynced ? BeatSpeed.label(for: $0) : "\($0.plain) s" }
        SettingTile("Speed", symbol: "metronome", value: value) {
            Group {
                if beatSynced {
                    // log2 travel gives each detent an even share of the track.
                    Slider(value: Binding(
                        get: { log2(max(speed ?? 1, BeatSpeed.detents.first!)) },
                        set: { setBeats(BeatSpeed.snapped(pow(2, $0))) }
                    ), in: log2(BeatSpeed.detents.first!) ... log2(BeatSpeed.detents.last!))
                    .sensoryFeedback(.selection, trigger: speed)
                } else {
                    Slider.withLog10Scale(value: session.binding(key, default: 1), in: 0.01 ... 60)
                }
            }
            .accessibilityLabel("Speed")
            .accessibilityValue(speed.map { beatSynced ? "\(BeatSpeed.label(for: $0)) per cycle" : "\($0.plain) seconds per cycle" } ?? "")
        }
        .availability(of: key, in: session)
    }

    private func setBeats(_ beats: Double) {
        guard beats != session.state[key] else { return }
        session.set(key, to: beats)
    }
}

/// An animation-specific parameter (tau, phi) on a log scale.
struct ParameterTile: View {
    let title: String
    let session: CoreSession
    let key: PropertyKey<DoubleConverter>

    var body: some View {
        SettingTile(title, value: session.state[key]?.plain) {
            Slider.withLog10Scale(value: session.binding(key, default: 1), in: 0.01 ... 80)
                .accessibilityLabel(title)
        }
        .availability(of: key, in: session)
    }
}

#Preview("Animation") {
    let session = CoreSession(link: FakeCoreLink.demo())
    NavigationStack {
        AnimationSettingsView(session: session)
            .navigationTitle("Nevyn's jacket")
    }
    .task { await session.run() }
}

#Preview("Beat-synced, preset held") {
    let link = FakeCoreLink.demo(board: .atomLite)
    link.values[CoreProps.beatSync.id] = "1"
    link.values[CoreProps.speed.id] = "0.500"
    let session = CoreSession(link: link)
    return NavigationStack {
        AnimationSettingsView(session: session)
            .navigationTitle("Nevyn's jacket")
    }
    .task { await session.run() }
}
