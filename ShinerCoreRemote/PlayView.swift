import SwiftUI
import ShinerCoreKit

/// The Play tab: the composite preview, lights, brightness, presets and the layer stack.
/// A core without a layer summary gets the single-layer view instead.
struct PlayView: View {
    let session: CoreSession
    /// The layer whose editor is open.
    @State var editing: Int?

    var body: some View {
        if showsSingleLayer {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PowerRow(session: session)
                    PresetChips(session: session)
                    SingleLayerView(session: session)
                }
                .padding()
            }
            .background(Color.groupedBackground)
        } else {
            stack
        }
    }

    /// Older firmware, or a summary that can't be read. Stays put while reconnecting.
    private var showsSingleLayer: Bool {
        let state = session.state
        if state.layerSummaryError != nil { return true }
        guard state.raw[CoreProps.layers.id] == nil else { return false }
        return session.connection == .connected ? !state.isAvailable(CoreProps.layers) : !state.raw.isEmpty
    }

    private var stack: some View {
        let state = session.state
        let layers = state.stack.map { Array($0.reversed()) }
        let baseSlot = state.stack?.first?.index
        return List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    CompositePreview(state: state)
                    if state.layerSummary?.source == .neighbor {
                        Label("Playing a neighbor's preset", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                PowerRow(session: session)
                PresetChips(session: session)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowSeparator(.hidden)

            Section {
                if let layers {
                    ForEach(layers) { layer in
                        Button {
                            session.selectLayer(layer.index)
                            editing = layer.index
                        } label: {
                            LayerRow(layer: layer, isBase: layer.index == baseSlot, state: state)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Remove", systemImage: "trash", role: .destructive) { session.removeLayer(layer.index) }
                                .tint(.red)
                        }
                    }
                    .onMove { source, destination in
                        guard let row = source.first, let own = state.ownLayers,
                              let move = LayerSummary(source: own.source, layers: state.stack ?? [])
                                  .layerMove(fromRow: row, toRow: destination)
                        else { return }
                        session.moveLayer(from: move.from, to: move.to)
                    }
                    if state.ownLayers?.firstEmptySlot != nil {
                        Button {
                            editing = session.addLayer()
                        } label: {
                            Label("Add layer", systemImage: "plus")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                } else {
                    ForEach(0 ..< 3, id: \.self) { _ in
                        LayerRow.placeholder
                    }
                }
            } header: {
                Text("Layers")
            } footer: {
                if let notice = session.layerMoveNotice {
                    Label(notice, systemImage: "cable.connector")
                } else if layers == nil, state.layerSummary?.source == .neighbor {
                    Text("Your layers show when the carousel comes back to this core.")
                } else if layers?.isEmpty == true {
                    Text("Nothing plays. Add a layer to light the strip.")
                } else if layers != nil {
                    Text("Front first. Drag to reorder; swipe to remove.")
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .sheet(item: Binding(get: { editing.map(EditorTarget.init) }, set: { editing = $0?.slot })) { target in
            NavigationStack {
                LayerEditorView(session: session, slot: target.slot, isBase: target.slot == baseSlot)
            }
        }
    }

    private struct EditorTarget: Identifiable {
        let slot: Int
        var id: Int { slot }
    }
}

/// What the strip shows: every layer blended, at the core's brightness, dark while the
/// lights are off.
struct CompositePreview: View {
    let state: CoreState

    var body: some View {
        let count = state[CoreProps.ledCount] ?? 0
        // LEDs look brighter than their duty cycle, and screens are gamma-encoded.
        StripPreview(layers: state.playingLayers ?? [], pixelCount: count > 0 ? count : 60,
                     caption: caption, brightness: pow(state.stripBrightness, 1 / 2.2), dots: 48)
            .frame(height: 72)
    }

    private var caption: String? {
        guard let layers = state.playingLayers else { return "" }
        if layers.isEmpty { return "Nothing plays" }
        if let unknown = layers.first(where: { RenderLibrary.animationDoc(named: $0.look.animation) == nil }) {
            return "No preview for \(unknown.look.animation)"
        }
        return nil
    }
}

/// The lights switch and the brightness fader, side by side.
struct PowerRow: View {
    let session: CoreSession

    var body: some View {
        let state = session.state
        let lightsOn = (state[CoreProps.mode] ?? 0) > 0
        let heldBy = state.lightsHold?.pin
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                PowerButton(isOn: lightsOn) { session.set(CoreProps.mode, to: lightsOn ? 0 : 1) }
                    .disabled(heldBy != nil)
                    .availability(of: CoreProps.mode, in: session)
                BrightnessFader(value: Binding(
                    get: { Double(state[CoreProps.brightness] ?? 0) },
                    set: { session.set(CoreProps.brightness, to: Int($0.rounded())) }
                ))
                .disabled(!lightsOn)
                .opacity(lightsOn ? 1 : 0.4)
                .availability(of: CoreProps.brightness, in: session)
            }
            HeldCaption(pin: heldBy)
        }
    }
}

struct PowerButton: View {
    let isOn: Bool
    let toggle: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: toggle) {
            Image(systemName: "power")
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 76, height: 76)
                .foregroundStyle(isOn ? .white : .secondary)
                .background(isOn ? Color.accentColor : Color.groupedSurface, in: .circle)
                .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: isOn)
        .accessibilityLabel("Lights")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// A full-height drag target: the whole capsule is the thumb.
struct BrightnessFader: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0 ... 255

    var body: some View {
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.groupedSurface)
                Capsule()
                    .fill(LinearGradient(colors: [Color.accentColor.opacity(0.45), Color.accentColor],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(76, geo.size.width * fraction))
                HStack {
                    Image(systemName: "sun.max.fill")
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Spacer()
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
            }
            .contentShape(.capsule)
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let f = min(max(drag.location.x / geo.size.width, 0), 1)
                value = range.lowerBound + f * (range.upperBound - range.lowerBound)
            })
        }
        .frame(height: 76)
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 10
            value = min(max(value + (direction == .increment ? step : -step), range.lowerBound), range.upperBound)
        }
    }
}

/// Switches the whole core to another preset; disabled while a switch holds one.
struct PresetChips: View {
    let session: CoreSession

    var body: some View {
        let selected = session.state[CoreProps.preset]
        let heldBy = session.state.presetHold?.pin
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(0 ..< CoreProps.presetCount, id: \.self) { preset in
                    let isSelected = preset == selected
                    Button { session.selectPreset(preset) } label: {
                        Text("\(preset)")
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.groupedSurface,
                                        in: .rect(cornerRadius: 14))
                            .overlay {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor, lineWidth: 2)
                                }
                            }
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preset \(preset)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .disabled(heldBy != nil)
            HeldCaption(pin: heldBy)
        }
        .availability(of: CoreProps.preset, in: session)
    }
}

/// One layer of the stack: what it plays, how it mixes, and a strip of it alone.
struct LayerRow: View {
    let layer: LayerSummary.Layer
    let isBase: Bool
    let state: CoreState

    var body: some View {
        let doc = state.animationDoc(for: layer.look.animation)
        let colors = [layer.look.color1, layer.look.color2].prefix(doc.colors)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("\(layer.index)")
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .accessibilityLabel("Layer \(layer.index)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(layer.look.animation).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                HStack(spacing: -6) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(Color(color))
                            .strokeBorder(.secondary.opacity(0.3))
                            .padding(2)
                            .background(Color.groupedSurface, in: .circle)  // separates the overlap
                            .frame(width: 26, height: 26)
                    }
                }
                .accessibilityHidden(true)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            StripPreview(looks: [soloLook], pixelCount: pixelCount, compact: true)
                .opacity(layer.gateOpen ? 1 : 0.35)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let mix = isBase ? "Base" : layer.look.blendMode
        return layer.gateOpen ? mix : "\(mix) · Off by \(gateControl ?? "its layer gate")"
    }

    /// The wired switch or button that gates this layer.
    private var gateControl: String? {
        guard let wiring = state[CoreProps.wiring], let docs = state.wiringDocs else { return nil }
        for pin in wiring.pins(controllingLayer: layer.index, docs: docs) {
            switch wiring.role(of: pin, docs: docs) {
            case .switch: return "the switch on \(pin)"
            case .button: return pin == docs.frontButton ? "the front button" : "the button on \(pin)"
            default: continue
            }
        }
        return nil
    }

    /// Drawn with Set: blended onto black, a Multiply or Darken layer would show nothing.
    private var soloLook: LayerLook {
        var look = layer.look
        look.blendMode = "Set"
        return look
    }

    private var pixelCount: Int {
        let count = state[CoreProps.ledCount] ?? 0
        return count > 0 ? count : 60
    }

    /// Stands in for a row until the stack is known.
    static var placeholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gradient Pulse").font(.headline)
                    Text("Screen").font(.subheadline)
                }
                Spacer()
            }
            RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.3)).frame(height: 12)
        }
        .padding(.vertical, 6)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

extension Color {
    init(_ pixel: PixelColor) {
        self.init(.sRGB, red: Double(pixel.r) / 255, green: Double(pixel.g) / 255, blue: Double(pixel.b) / 255)
    }
}

#Preview("Play") {
    let session = CoreSession(link: FakeCoreLink.demo())
    NavigationStack {
        PlayView(session: session)
            .navigationTitle("Nevyn's jacket")
    }
    .task { await session.run() }
}

#Preview("Connected during a neighbor's turn, held") {
    let link = FakeCoreLink.demo(board: .atomLite)
    link.values[CoreProps.pinStatus.id] = "0306004dff"  // G25 and G22 closed
    link.values[CoreProps.mode.id] = "0"
    link.neighborLayers = [FakeCoreLink.layer("Rainbow", color: "0 0 0", speed: 6, tau: 2, phi: 1)]
    let session = CoreSession(link: link)
    return NavigationStack {
        PlayView(session: session)
            .navigationTitle("Vindarnas hus")
    }
    .task { await session.run() }
}

#Preview("Older firmware") {
    let link = FakeCoreLink.demo()
    link.exposesLayerSummary = false
    let session = CoreSession(link: link)
    return NavigationStack {
        PlayView(session: session)
            .navigationTitle("Nevyn's jacket")
    }
    .task { await session.run() }
}
