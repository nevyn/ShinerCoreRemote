#if DEBUG
import SwiftUI

/// Design iterations, on mock data. Launch with `-ui-playground <screen>`.
enum PlaygroundScreen: String, CaseIterable, Identifiable {
    case index, tiles, stage, layer, setup, list, empty
    var id: String { rawValue }

    /// `-ui-playground [screen]`; no screen opens the index.
    static var fromLaunchArguments: PlaygroundScreen? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-ui-playground") else { return nil }
        guard args.indices.contains(flag + 1), !args[flag + 1].hasPrefix("-") else { return .index }
        guard let screen = PlaygroundScreen(rawValue: args[flag + 1]) else {
            preconditionFailure("-ui-playground wants one of \(allCases.map(\.rawValue))")
        }
        return screen
    }

    var title: String {
        switch self {
        case .index: "Iterations"
        case .tiles: "A. Tiles, tidied"
        case .stage: "B. Stage"
        case .layer: "B. Layer editor"
        case .setup: "B. Setup"
        case .list: "Core list"
        case .empty: "Core list, empty"
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.82, green: 0.22, blue: 0.92)
    static let background = Color(white: 0.04)
    static let surface = Color(white: 0.11)
    static let raised = Color(white: 0.17)
}

struct PlaygroundRoot: View {
    let screen: PlaygroundScreen
    @State private var core = MockCore()

    var body: some View {
        Group {
            switch screen {
            case .index:
                NavigationStack {
                    List(PlaygroundScreen.allCases.dropFirst()) { s in
                        NavigationLink(s.title) { PlaygroundRoot(screen: s) }
                    }
                    .navigationTitle("Iterations")
                }
            case .tiles: TilesIteration(core: core)
            case .stage: StageIteration(core: core)
            case .layer: NavigationStack { LayerEditor(core: core, index: 1) }
            case .setup: NavigationStack { SetupIteration(core: core) }
            case .list: CoreListIteration(cores: ["Nevyn's jacket", "Vindarnas hus", "Demo core"])
            case .empty: CoreListIteration(cores: [])
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

// MARK: - A. Tiles, tidied: today's grid, fixed

/// The cheapest step: same layout and tabs, but every tile reads the same
/// way (label top-left, value top-right with units), raw wire values gone,
/// tau/phi named per animation and hidden when unused.
struct TilesIteration: View {
    @Bindable var core: MockCore

    var body: some View {
        let layer = $core.layers[core.selectedLayer]
        let anim = layer.wrappedValue.animation
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Picker("Preset", selection: $core.preset) {
                        ForEach(0..<5, id: \.self) { Text("Preset \($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LayerChips(core: core)

                    LEDStripView(layers: [layer.wrappedValue], count: 32)
                        .frame(height: 44)

                    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            Tile("Animation", symbol: anim.symbol) {
                                Stepper(anim.rawValue) { step(layer, 1) } onDecrement: { step(layer, -1) }
                                    .font(.headline)
                            }
                            .gridCellColumns(2)
                        }
                        GridRow {
                            Tile("Primary", symbol: "paintpalette") {
                                ColorPicker("Primary", selection: colorBinding(layer.color1)).labelsHidden()
                            }
                            .opacity(anim.colorsUsed >= 1 ? 1 : 0.35)
                            Tile("Secondary", symbol: "paintpalette") {
                                ColorPicker("Secondary", selection: colorBinding(layer.color2)).labelsHidden()
                            }
                            .opacity(anim.colorsUsed >= 2 ? 1 : 0.35)
                        }
                        GridRow {
                            Tile("Speed", symbol: "metronome", value: String(format: "%.1f s", layer.wrappedValue.speed)) {
                                Slider(value: layer.speed, in: 0.1...20)
                            }
                            Tile("Beat sync", symbol: "waveform") {
                                Toggle("Beat sync", isOn: layer.beatSync).labelsHidden()
                            }
                        }
                        if let params = anim.parameters {
                            GridRow {
                                Tile(params.tau, value: String(format: "%.1f", layer.wrappedValue.tau)) {
                                    Slider(value: layer.tau, in: 0.1...40)
                                }
                                Tile(params.phi, value: String(format: "%.1f", layer.wrappedValue.phi)) {
                                    Slider(value: layer.phi, in: 0.1...40)
                                }
                            }
                        }
                        GridRow {
                            Tile("Blend", symbol: "square.stack.3d.down.right") {
                                Picker("Blend", selection: layer.blend) {
                                    ForEach(["Add", "Screen", "Multiply", "Average", "Subtract", "Set"], id: \.self) { Text($0) }
                                }
                                .labelsHidden()
                            }
                            .gridCellColumns(2)
                        }
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle(core.name)
        }
    }

    private func step(_ layer: Binding<MockLayer>, _ delta: Int) {
        let all = Anim.allCases
        let i = all.firstIndex(of: layer.wrappedValue.animation)! + delta
        if all.indices.contains(i) { layer.wrappedValue.animation = all[i] }
    }
}

/// Ten layers as chips; a lit dot marks a layer that has an animation.
struct LayerChips: View {
    @Bindable var core: MockCore

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<10, id: \.self) { i in
                let active = core.layers[i].animation != .nothing
                Button { core.selectedLayer = i } label: {
                    VStack(spacing: 4) {
                        Text("\(i)").font(.callout.monospacedDigit().weight(.semibold))
                        Circle()
                            .fill(active ? core.layers[i].color1.color : .clear)
                            .stroke(.secondary, lineWidth: active ? 0 : 1)
                            .frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(core.selectedLayer == i ? Theme.raised : Theme.surface, in: .rect(cornerRadius: 10))
                    .overlay {
                        if core.selectedLayer == i {
                            RoundedRectangle(cornerRadius: 10).stroke(Theme.accent, lineWidth: 1.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(active ? "Layer \(i), \(core.layers[i].animation.rawValue)" : "Layer \(i), empty")
            }
        }
    }
}

struct Tile<Content: View>: View {
    let title: String
    var symbol: String?
    var value: String?
    @ViewBuilder var content: Content

    init(_ title: String, symbol: String? = nil, value: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.value = value
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let symbol {
                    Label(title, systemImage: symbol)
                } else {
                    Text(title)
                }
                Spacer(minLength: 4)
                if let value {
                    Text(value)
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            content
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
    }
}

// MARK: - B. Stage: what you reach for in the dark

/// The bold step. Three tabs instead of four: Play holds what changes during
/// a night out (power, brightness, preset, the layer stack); Setup holds
/// what is set once (strip, power, mesh); Wiring stays as it is.
struct StageIteration: View {
    @Bindable var core: MockCore
    @State private var editing: Int?

    var body: some View {
        TabView {
            NavigationStack { play }
                .tabItem { Label("Play", systemImage: "sparkles") }
            Text("Wiring, unchanged")
                .tabItem { Label("Wiring", systemImage: "cable.connector") }
            NavigationStack { SetupIteration(core: core) }
                .tabItem { Label("Setup", systemImage: "slider.horizontal.3") }
        }
    }

    private var play: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LEDStripView(layers: core.layers, count: 36, brightness: core.lightsOn ? 0.3 + 0.7 * core.brightness / 255 : 0)
                    .frame(height: 80)
                    .padding(.horizontal, 10)
                    .background(.black, in: .rect(cornerRadius: 20))

                HStack(spacing: 12) {
                    PowerButton(isOn: $core.lightsOn)
                    BrightnessFader(value: $core.brightness)
                        .disabled(!core.lightsOn)
                        .opacity(core.lightsOn ? 1 : 0.4)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Preset")
                    HStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { i in
                            PresetChip(index: i, look: MockCore.presetLooks[i], selected: core.preset == i) {
                                core.preset = i
                            }
                        }
                    }
                    .disabled(core.presetHeldBy != nil)
                    if let pin = core.presetHeldBy {
                        Label("Held by the switch on \(pin)", systemImage: "switch.2")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Layers", trailing: "Bottom first")
                    VStack(spacing: 1) {
                        ForEach(core.activeLayers, id: \.self) { i in
                            Button { editing = i } label: { LayerRow(index: i, layer: core.layers[i]) }
                                .buttonStyle(.plain)
                        }
                        Button {
                            if let free = core.layers.firstIndex(of: .empty) {
                                core.layers[free] = MockLayer(animation: .twinkle, tau: 3, phi: 1)
                                editing = free
                            }
                        } label: {
                            Label("Add layer", systemImage: "plus")
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .background(Theme.surface)
                    }
                    .clipShape(.rect(cornerRadius: 16))
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(core.name)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Label("Connected", systemImage: "circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .sheet(item: Binding(get: { editing.map(LayerID.init) }, set: { editing = $0?.index })) { id in
            NavigationStack { LayerEditor(core: core, index: id.index) }
        }
    }

    private struct LayerID: Identifiable { let index: Int; var id: Int { index } }
}

struct SectionTitle: View {
    let title: String
    var trailing: String?
    init(_ title: String, trailing: String? = nil) { self.title = title; self.trailing = trailing }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            if let trailing { Text(trailing).font(.footnote).foregroundStyle(.secondary) }
        }
    }
}

struct PowerButton: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Image(systemName: "power")
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 76, height: 76)
                .foregroundStyle(isOn ? .white : .secondary)
                .background(isOn ? Theme.accent : Theme.surface, in: .circle)
                .shadow(color: isOn ? Theme.accent.opacity(0.6) : .clear, radius: 14)
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
    var range: ClosedRange<Double> = 0...255

    var body: some View {
        GeometryReader { geo in
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.5), Theme.accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(76, geo.size.width * fraction))
                HStack {
                    Image(systemName: "sun.max.fill")
                    Text("\(Int(fraction * 100))%").monospacedDigit().contentTransition(.numericText())
                    Spacer()
                }
                .font(.headline)
                .padding(.horizontal, 22)
            }
            .contentShape(.capsule)
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let f = min(max(g.location.x / geo.size.width, 0), 1)
                value = range.lowerBound + f * (range.upperBound - range.lowerBound)
            })
        }
        .frame(height: 76)
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(Int(value / range.upperBound * 100)) percent")
        .accessibilityAdjustableAction { dir in
            value = min(max(value + (dir == .increment ? 25 : -25), range.lowerBound), range.upperBound)
        }
    }
}

struct PresetChip: View {
    let index: Int
    let look: [MockLayer]
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                LEDStripView(layers: look, count: 8, glow: false).frame(height: 10)
                Text("\(index)").font(.title3.monospacedDigit().weight(.semibold))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(selected ? Theme.raised : Theme.surface, in: .rect(cornerRadius: 14))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 14).stroke(Theme.accent, lineWidth: 2) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Preset \(index)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct LayerRow: View {
    let index: Int
    let layer: MockLayer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: layer.animation.symbol)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(layer.animation.rawValue).font(.headline)
                    Text(index == 0 ? "Base · \(speed)" : "\(layer.blend) · \(speed)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: -6) {
                    ForEach(Array([layer.color1, layer.color2].prefix(layer.animation.colorsUsed).enumerated()), id: \.offset) {
                        Circle().fill($0.element.color).stroke(Theme.surface, lineWidth: 2).frame(width: 22, height: 22)
                    }
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            LEDStripView(layers: [layer], count: 40, glow: false).frame(height: 6)
        }
        .padding(14)
        .background(Theme.surface)
        .contentShape(.rect)
    }

    private var speed: String { layer.beatSync ? "beat synced" : String(format: "%.1f s cycle", layer.speed) }
}

// MARK: - B. Layer editor

struct LayerEditor: View {
    @Bindable var core: MockCore
    let index: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let layer = $core.layers[index]
        let anim = layer.wrappedValue.animation
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LEDStripView(layers: [layer.wrappedValue], count: 36)
                    .frame(height: 64)
                    .padding(.horizontal, 10)
                    .background(.black, in: .rect(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Animation")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                        ForEach(Anim.allCases.dropFirst()) { a in
                            AnimationCard(anim: a, layer: layer.wrappedValue, selected: a == anim) {
                                layer.wrappedValue.animation = a
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Colors")
                    HStack(spacing: 16) {
                        Swatch(title: "Primary", color: colorBinding(layer.color1))
                            .opacity(anim.colorsUsed >= 1 ? 1 : 0.3)
                        Button {
                            layer.wrappedValue.swapColors()
                        } label: {
                            Image(systemName: "arrow.left.arrow.right").font(.headline).frame(width: 44, height: 44)
                        }
                        .disabled(anim.colorsUsed < 2)
                        .accessibilityLabel("Swap colors")
                        Swatch(title: "Secondary", color: colorBinding(layer.color2))
                            .opacity(anim.colorsUsed >= 2 ? 1 : 0.3)
                    }
                    .frame(maxWidth: .infinity)
                    if anim.colorsUsed < 2 {
                        Text(anim.colorsUsed == 0 ? "\(anim.rawValue) makes its own colors." : "\(anim.rawValue) uses only the primary color.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Motion")
                    VStack(spacing: 1) {
                        FormRow {
                            Toggle(isOn: layer.beatSync) { Label("Follow the beat", systemImage: "waveform") }
                        }
                        FormRow {
                            LabeledSlider(title: layer.wrappedValue.beatSync ? "Beats per cycle" : "Seconds per cycle",
                                          value: layer.speed, range: 0.1...20, format: "%.1f")
                        }
                        if let params = anim.parameters {
                            FormRow { LabeledSlider(title: params.tau, value: layer.tau, range: 0.1...40, format: "%.1f") }
                            FormRow { LabeledSlider(title: params.phi, value: layer.phi, range: 0.1...40, format: "%.1f") }
                        }
                    }
                    .clipShape(.rect(cornerRadius: 16))
                }

                if index > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Blend")
                        FormRow {
                            Picker("Mix with the layers below", selection: layer.blend) {
                                ForEach(["Add", "Screen", "Multiply", "Average", "Subtract", "Set"], id: \.self) { Text($0) }
                            }
                        }
                        .clipShape(.rect(cornerRadius: 16))
                    }
                }

                Button("Remove layer", role: .destructive) {
                    layer.wrappedValue = .empty
                    dismiss()
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.surface, in: .rect(cornerRadius: 16))
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(index == 0 ? "Base layer" : "Layer \(index)")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
}

struct AnimationCard: View {
    let anim: Anim
    let layer: MockLayer
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                LEDStripView(layers: [preview], count: 12, glow: false).frame(height: 10)
                Text(anim.rawValue).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.raised : Theme.surface, in: .rect(cornerRadius: 12))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 12).stroke(Theme.accent, lineWidth: 2) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Each card previews its own animation in this layer's colors, with
    /// parameters scaled to a 12-pixel strip.
    private var preview: MockLayer {
        var l = layer
        l.animation = anim
        (l.tau, l.phi) = (3, 2)
        if l.speed < 1 { l.speed = 1 }
        return l
    }
}

struct Swatch: View {
    let title: String
    @Binding var color: Color

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 72, height: 72)
                .shadow(color: color.opacity(0.6), radius: 12)
                .overlay {
                    // The native well, stretched invisibly over the swatch, keeps the system picker.
                    ColorPicker(title, selection: $color).labelsHidden().scaleEffect(2.6).opacity(0.02)
                }
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

struct FormRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Theme.surface)
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

// MARK: - B. Setup: set once, then forget

struct SetupIteration: View {
    @Bindable var core: MockCore

    var body: some View {
        Form {
            Section {
                LabeledContent("Owner") {
                    TextField("Your name", text: $core.owner).multilineTextAlignment(.trailing)
                }
                Picker("When powered on", selection: $core.bootPreset) {
                    Text("Resume as it was").tag(-1)
                    ForEach(0..<5, id: \.self) { Text("Lights on, preset \($0)").tag($0) }
                }
            } header: {
                Text("This core")
            } footer: {
                Text("The core names itself after its owner: \(core.name).")
            }

            Section("LED strip") {
                Stepper(value: $core.ledCount, in: 0...800) {
                    LabeledContent("LEDs", value: "\(core.ledCount)")
                }
                Picker("Color order", selection: $core.ledOrder) {
                    ForEach(["RGB", "GRB", "BGR"], id: \.self) { Text($0) }
                }
                Picker("Power limit", selection: $core.maxCurrent) {
                    Text("None").tag(0)
                    ForEach([500, 1000, 2000, 3000, 5000], id: \.self) {
                        Text(String(format: "%.1f A", Double($0) / 1000)).tag($0)
                    }
                }
            }

            Section {
                Toggle("Microphone", isOn: $core.mic)
            } header: {
                Text("Sound")
            } footer: {
                Text("Needed for beat sync and Beat Pulse.")
            }

            Section {
                Toggle("Mesh radio", isOn: $core.mesh)
                Toggle("Play the shared show", isOn: $core.meshShow).disabled(!core.mesh)
                LabeledContent("Group") {
                    TextField("Everyone", text: $core.meshGroup).multilineTextAlignment(.trailing)
                }
                .disabled(!core.mesh)
            } header: {
                Text("Mesh")
            } footer: {
                Text("Cores in the same group sync their beat and take turns choosing the show.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Setup")
    }
}

// MARK: - Core list

struct CoreListIteration: View {
    let cores: [String]

    var body: some View {
        NavigationStack {
            Group {
                if cores.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        RadarPulse().frame(width: 160, height: 160)
                        Text("Looking for cores").font(.title2.weight(.semibold))
                        Text("Power up a core and hold it close to your phone.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Try the demo core") {}
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .padding(.bottom)
                    }
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(Array(cores.enumerated()), id: \.offset) { i, name in
                                NavigationLink(value: name) {
                                    HStack(spacing: 14) {
                                        Image(systemName: "sparkles")
                                            .font(.title3)
                                            .foregroundStyle(Theme.accent)
                                            .frame(width: 40, height: 40)
                                            .background(Theme.raised, in: .circle)
                                        Text(name).font(.headline)
                                        Spacer()
                                        SignalBars(level: 3 - i)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        } footer: {
                            Text("Missing one? Power it up and hold it close.")
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.background)
            .navigationTitle("Nearby cores")
        }
    }
}

struct SignalBars: View {
    let level: Int
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < level ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 4, height: CGFloat(6 + i * 4))
            }
        }
        .accessibilityLabel(["Out of range", "Weak signal", "Good signal", "Close by"][max(0, min(level, 3))])
    }
}

struct RadarPulse: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3) { i in
                    let p = (t / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(Theme.accent.opacity(1 - p), lineWidth: 2)
                        .scaleEffect(0.3 + 0.7 * p)
                }
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
        }
        .accessibilityHidden(true)
    }
}

private func colorBinding(_ rgb: Binding<RGB>) -> Binding<Color> {
    Binding(get: { rgb.wrappedValue.color }, set: { rgb.wrappedValue = RGB($0) })
}

#Preview("A. Tiles") { PlaygroundRoot(screen: .tiles) }
#Preview("B. Stage") { PlaygroundRoot(screen: .stage) }
#Preview("B. Layer editor") { PlaygroundRoot(screen: .layer) }
#Preview("B. Setup") { PlaygroundRoot(screen: .setup) }
#Preview("Core list") { PlaygroundRoot(screen: .list) }
#Preview("Core list, empty") { PlaygroundRoot(screen: .empty) }
#endif
