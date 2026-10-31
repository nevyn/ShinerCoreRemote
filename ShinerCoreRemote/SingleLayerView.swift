import SwiftUI
import ShinerCoreKit

/// One layer at a time, picked by number: Play's layer section for cores whose firmware
/// predates the layer summary.
struct SingleLayerView: View {
    let session: CoreSession

    var body: some View {
        let state = session.state
        let docs = state.documentation
        let animation = state[CoreProps.animation]
        let animationDoc = animation.map(state.animationDoc(for:)) ?? .generic
        VStack(alignment: .leading, spacing: 12) {
            LayerPicker(session: session)
            LayerPreview(state: state)
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    AnimationTile(session: session, options: docs?.animations ?? [])
                        .gridCellColumns(2)
                }
                GridRow {
                    ColorTile(title: "Primary", session: session, key: CoreProps.color,
                              used: animationDoc.colors >= 1)
                    ColorTile(title: "Secondary", session: session, key: CoreProps.color2,
                              used: animationDoc.colors >= 2)
                }
                if let animation, let note = Self.colorNote(animation: animation, colors: animationDoc.colors) {
                    GridRow {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .gridCellColumns(2)
                    }
                }
                GridRow {
                    SpeedTile(session: session)
                    SettingTile("Beat sync", symbol: "waveform") {
                        Toggle("Beat sync", isOn: session.boolBinding(CoreProps.beatSync))
                            .labelsHidden()
                    }
                    .availability(of: CoreProps.beatSync, in: session)
                }
                // Full width: parameter names such as "Counter-wave length" need the room.
                if let tau = animationDoc.tau {
                    GridRow {
                        ParameterTile(title: tau, session: session, key: CoreProps.tau).gridCellColumns(2)
                    }
                }
                if let phi = animationDoc.phi {
                    GridRow {
                        ParameterTile(title: phi, session: session, key: CoreProps.phi).gridCellColumns(2)
                    }
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
    }
}

extension SingleLayerView {
    /// Explains a dimmed color tile; nil when the animation reads both colors or draws nothing.
    static func colorNote(animation: String, colors: Int) -> String? {
        guard animation != RenderLibrary.nothing else { return nil }
        return switch colors {
        case 0: "\(animation) makes its own colors."
        case 1: "\(animation) uses only the primary color."
        default: nil
        }
    }
}

/// The selected layer drawn on its own, labelled so that nobody takes it for the whole strip.
struct LayerPreview: View {
    let state: CoreState

    var body: some View {
        let layer = state[CoreProps.layer] ?? 0
        VStack(alignment: .leading, spacing: 6) {
            StripPreview(looks: look.map { [$0] } ?? [], pixelCount: pixelCount, caption: caption)
            Text("Layer \(layer) alone")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Drawn with Set rather than its blend mode: blended onto black, a Multiply or
    /// Darken layer would show nothing at all.
    private var look: LayerLook? {
        guard var look = state.layerLook else { return nil }
        look.blendMode = "Set"
        return look
    }

    private var pixelCount: Int {
        let count = state[CoreProps.ledCount] ?? 0
        return count > 0 ? count : 60
    }

    private var caption: String? {
        guard let animation = state[CoreProps.animation] else { return "" }
        if animation == RenderLibrary.nothing { return "Nothing plays on this layer" }
        if RenderLibrary.animationDoc(named: animation) == nil { return "No preview for \(animation)" }
        return nil
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

/// A big swatch that opens the system color picker. Dimmed while the animation ignores
/// the color, but still editable: other animations use it.
struct ColorTile: View {
    let title: String
    let session: CoreSession
    let key: PropertyKey<ColorConverter>
    var used = true

    var body: some View {
        let color = session.binding(key, default: .black)
        let known = session.state[key] != nil
        SettingTile(title, symbol: "paintpalette") {
            ZStack {
                // The stretched native well takes the taps; absent until loaded, as dimming would show its ring through the swatch.
                if known {
                    GeometryReader { geo in
                        ColorPicker(title, selection: color, supportsOpacity: false)
                            .labelsHidden()
                            .scaleEffect(x: geo.size.width / 24, y: geo.size.height / 24)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                RoundedRectangle(cornerRadius: 10)
                    .fill(known ? color.wrappedValue : Color.secondary.opacity(0.15))
                    .strokeBorder(.secondary.opacity(0.3))
                    .allowsHitTesting(false)
            }
            .frame(height: 56)
            .clipShape(.rect(cornerRadius: 10))
        }
        .overlay {
            // A veil rather than opacity, which would let the stretched well show through.
            if !used {
                Color.groupedSurface.opacity(0.6)
                    .clipShape(.rect(cornerRadius: 16))
                    .allowsHitTesting(false)
            }
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

#Preview("Single layer") {
    let link = FakeCoreLink.demo()
    link.exposesLayerSummary = false
    let session = CoreSession(link: link)
    return ScrollView {
        SingleLayerView(session: session).padding()
    }
    .task { await session.run() }
}

#Preview("Single color, beat-synced") {
    let link = FakeCoreLink.demo()
    link.exposesLayerSummary = false
    link.values[CoreProps.animation.id] = "Single Wave"
    link.values[CoreProps.beatSync.id] = "1"
    link.values[CoreProps.speed.id] = "0.500"
    let session = CoreSession(link: link)
    return ScrollView {
        SingleLayerView(session: session).padding()
    }
    .task { await session.run() }
}
