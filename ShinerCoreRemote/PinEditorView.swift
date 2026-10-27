import SwiftUI
import ShinerCoreKit

/// Edits one pin's role. Every change writes the whole wiring through
/// `session.set`; a change to or from LEDs asks first, because it restarts the core.
/// The front button only picks a button action.
struct PinEditorView: View {
    let session: CoreSession
    let pin: String
    let docs: WiringDocs
    @State private var draft: RoleDraft
    /// The range handles' values while a drag is in progress; written when it ends.
    @State private var draggedRange: ClosedRange<Double>?
    @State private var pendingLEDKind: RoleKind?
    @Environment(\.dismiss) private var dismiss

    init(session: CoreSession, pin: String, docs: WiringDocs) {
        self.session = session
        self.pin = pin
        self.docs = docs
        _draft = State(initialValue: RoleDraft(session.state[CoreProps.wiring]?.role(of: pin, docs: docs)))
    }

    private var storedRole: PinRole? { session.state[CoreProps.wiring]?.role(of: pin, docs: docs) }
    private var isFrontButton: Bool { pin == docs.frontButton }
    private var layout: BoardLayout? { BoardLayout(board: docs.board) }
    private var boardName: String { layout?.name ?? docs.board }
    private var params: [KnobParam] { KnobParam.allCases.filter { !$0.targets(in: docs).isEmpty } }
    private var channels: [KnobTarget.ColorChannel] {
        draft.param.targets(in: docs).compactMap { if case .color(_, let channel) = $0 { channel } else { nil } }
    }

    private var kinds: [RoleKind] {
        RoleKind.allCases.filter {
            switch $0 {
            case .knob: docs.analog.contains(pin) && !params.isEmpty
            case .leds: docs.led.contains(pin)
            default: true
            }
        }
    }

    /// Another LED pin, drawn faded so the new wires have something to orient by.
    private var contextLED: String? {
        docs.pins.first { $0 != pin && session.state[CoreProps.wiring]?[$0] == .leds }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isFrontButton {
                    buttonSection
                } else {
                    pinSections
                }
            }
            .formStyle(.grouped) // macOS defaults to .columns: inline headers, no section padding
            .navigationTitle(isFrontButton ? "Front button" : pin)
            .toolbar { Button("Done") { dismiss() } }
            .confirmationDialog("Changing LED pins restarts the core",
                                isPresented: Binding(get: { pendingLEDKind != nil },
                                                     set: { if !$0 { pendingLEDKind = nil } }),
                                titleVisibility: .visible, presenting: pendingLEDKind) { kind in
                Button("Change and restart") { setKind(kind) }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onChange(of: draft) { commit() }
        .onChange(of: storedRole) { _, role in
            if role != draft.role { draft = RoleDraft(role) }  // the device's wiring changed underneath
        }
    }

    @ViewBuilder private var pinSections: some View {
        Section {
            Picker("Wired", selection: kindBinding) {
                ForEach(kinds) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text("What's wired to \(pin)?")
        } footer: {
            if !docs.analog.contains(pin), !docs.analogPins.isEmpty {
                Text("Knobs only work on \(docs.analogPins.joined(separator: ", ")) on the \(boardName).")
            }
        }

        if draft.kind != .nothing {
            Section("How to wire it") {
                if let layout {
                    WiringDiagramView(board: layout, pin: pin, kind: draft.kind, contextLED: contextLED)
                        .frame(height: 340)
                        .listRowInsets(EdgeInsets())
                        .accessibilityHidden(true)
                }
                WiringSteps(layout: layout, boardName: boardName, pin: pin, kind: draft.kind)
            }
        }

        switch draft.kind {
        case .nothing: EmptyView()
        case .leds: ledSection
        case .switch: switchSection
        case .button: buttonSection
        case .knob: knobSections
        }
    }

    private func commit() {
        if draft.indexIsPreset, draft.index > 4 {
            draft.index = 4  // re-enters commit through onChange
            return
        }
        guard var wiring = session.state[CoreProps.wiring], draft.role != wiring.role(of: pin, docs: docs) else { return }
        wiring[pin] = draft.role
        session.set(CoreProps.wiring, to: wiring)
    }

    private var kindBinding: Binding<RoleKind> {
        Binding(get: { draft.kind }, set: { kind in
            if (kind == .leds) != (draft.kind == .leds) {
                pendingLEDKind = kind
            } else {
                setKind(kind)
            }
        })
    }

    private func setKind(_ kind: RoleKind) {
        var next = draft
        next.kind = kind
        if kind == .knob, !params.contains(next.param), let first = params.first {
            next.selectParam(first, docs: docs)
        }
        draft = next
    }

    private func indexPicker(isPreset: Bool) -> some View {
        Picker(isPreset ? "Preset" : "Layer", selection: $draft.index) {
            ForEach(0 ..< (isPreset ? 5 : 10), id: \.self) { Text("\($0)").tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var ledSection: some View {
        Section {
            Label("Every LED pin shows the same animation. Changing a pin to or from LEDs restarts the core.",
                  systemImage: "arrow.clockwise")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var switchSection: some View {
        Section {
            Picker("When closed", selection: $draft.switchAction) {
                ForEach(SwitchChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            if draft.switchAction.needsIndex { indexPicker(isPreset: draft.switchAction == .preset) }
        } footer: {
            Text("While the switch is closed it holds this, and the app can't change it.")
        }
    }

    private var buttonSection: some View {
        Section {
            Picker("When pressed", selection: $draft.buttonAction) {
                ForEach(ButtonChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            if draft.buttonAction.needsIndex { indexPicker(isPreset: draft.buttonAction == .preset) }
        } footer: {
            let notes = [
                draft.buttonAction == .nextPreset ? "Hold for half a second to turn the lights on or off." : nil,
                isFrontButton ? "This is the button on the face of the core, so it needs no wiring. Holding it while the core starts clears all settings." : nil,
            ].compactMap { $0 }
            if !notes.isEmpty { Text(notes.joined(separator: " ")) }
        }
    }

    @ViewBuilder private var knobSections: some View {
        let target = draft.target
        let range = draggedRange ?? draft.range
        let live = liveValue(in: range)
        Section("Controls") {
            Picker("Target", selection: Binding(get: { draft.param }, set: { draft.selectParam($0, docs: docs) })) {
                ForEach(params) { Text($0.rawValue).tag($0) }
            }
            if draft.param.isLayer { indexPicker(isPreset: false) }
            if draft.param.isColor {
                Picker("Channel", selection: $draft.channel) {
                    ForEach(channels, id: \.self) { Text($0.shortName).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        Section {
            RangeSliderView(
                range: Binding(
                    get: { target.sliderFraction(of: range.lowerBound) ... target.sliderFraction(of: range.upperBound) },
                    set: { draggedRange = target.value(atSliderFraction: $0.lowerBound) ... target.value(atSliderFraction: $0.upperBound) }),
                live: live.map(target.sliderFraction(of:)),
                describe: target.format,
                onEnded: {
                    if let draggedRange { draft.range = draggedRange }
                    draggedRange = nil
                })
                .frame(height: 44)
            HStack {
                Text(target.format(draft.reversed ? range.upperBound : range.lowerBound))
                Spacer()
                if let live { Text("now \(target.format(live))").foregroundStyle(.orange) }
                Spacer()
                Text(target.format(draft.reversed ? range.lowerBound : range.upperBound))
            }
            .font(.subheadline.monospacedDigit())
            Toggle("Reverse", isOn: $draft.reversed)
        } header: {
            Text("Range")
        } footer: {
            Text("Knob fully left to fully right sweeps between the two handles.")
        }
    }

    /// What the knob writes at its current position; nil before pinStatus arrives.
    private func liveValue(in range: ClosedRange<Double>) -> Double? {
        guard let position = session.state[CoreProps.pinStatus]?.state(of: pin, in: docs)?.position else { return nil }
        let (min, max) = draft.reversed ? (range.upperBound, range.lowerBound) : (range.lowerBound, range.upperBound)
        return draft.target.knobValue(min: min, max: max, position: Double(position) / 255)
    }
}

// MARK: - Draft

enum SwitchChoice: String, CaseIterable, Identifiable {
    case lightsOff = "Lights off", lightsOn = "Lights on", preset = "Preset", layerOn = "Layer on"
    var id: Self { self }
    var needsIndex: Bool { self == .preset || self == .layerOn }
}

enum ButtonChoice: String, CaseIterable, Identifiable {
    case nextPreset = "Next preset", toggleLights = "Lights on/off", preset = "Preset", toggleLayer = "Layer on/off"
    var id: Self { self }
    var needsIndex: Bool { self == .preset || self == .toggleLayer }
}

/// The editor's choices for every role at once, so flipping between roles
/// keeps what was picked for each. `role` is what gets written.
struct RoleDraft: Equatable {
    var kind: RoleKind = .nothing
    var switchAction: SwitchChoice = .lightsOff
    var buttonAction: ButtonChoice = .nextPreset
    /// The preset (0-4) or layer (0-9) of whichever action or knob target needs one.
    var index = 0
    var param: KnobParam = .brightness
    var channel: KnobTarget.ColorChannel = .hue
    /// Knob range in target units, low to high; `reversed` makes the high end the knob's min.
    var range: ClosedRange<Double> = KnobTarget.brightness.defaultRange
    var reversed = false

    init(_ role: PinRole?) {
        kind = RoleKind(role)
        switch role {
        case nil, .leds: break
        case .switch(let action):
            switch action {
            case .lightsOff: switchAction = .lightsOff
            case .lightsOn: switchAction = .lightsOn
            case .preset(let n): switchAction = .preset; index = n
            case .layerOn(let n): switchAction = .layerOn; index = n
            }
        case .button(let action):
            switch action {
            case .nextPreset: buttonAction = .nextPreset
            case .toggleLights: buttonAction = .toggleLights
            case .preset(let n): buttonAction = .preset; index = n
            case .toggleLayer(let n): buttonAction = .toggleLayer; index = n
            }
        case .knob(let knob):
            param = KnobParam(knob.target)
            if case .color(_, let c) = knob.target { channel = c }
            index = knob.layer ?? 0
            range = Swift.min(knob.min, knob.max) ... Swift.max(knob.min, knob.max)
            reversed = knob.min > knob.max
        }
    }

    var target: KnobTarget { param.target(channel) }

    var indexIsPreset: Bool {
        (kind == .switch && switchAction == .preset) || (kind == .button && buttonAction == .preset)
    }

    var role: PinRole? {
        switch kind {
        case .nothing: return nil
        case .leds: return .leds
        case .switch:
            switch switchAction {
            case .lightsOff: return .switch(.lightsOff)
            case .lightsOn: return .switch(.lightsOn)
            case .preset: return .switch(.preset(Swift.min(index, 4)))
            case .layerOn: return .switch(.layerOn(index))
            }
        case .button:
            switch buttonAction {
            case .nextPreset: return .button(.nextPreset)
            case .toggleLights: return .button(.toggleLights)
            case .preset: return .button(.preset(Swift.min(index, 4)))
            case .toggleLayer: return .button(.toggleLayer(index))
            }
        case .knob:
            let (min, max) = reversed ? (range.upperBound, range.lowerBound) : (range.lowerBound, range.upperBound)
            return .knob(Knob(target: target, layer: target.isLayerTarget ? index : nil, min: min, max: max))
        }
    }

    /// Picks a knob parameter with a channel that `docs` offers and the parameter's default range.
    mutating func selectParam(_ param: KnobParam, docs: WiringDocs) {
        self.param = param
        let offered = param.targets(in: docs)
        if !offered.contains(param.target(channel)), case .color(_, let c)? = offered.first { channel = c }
        range = target.defaultRange
    }
}

/// Knob targets as the editor groups them: color channels sit under their color.
enum KnobParam: String, CaseIterable, Identifiable {
    case brightness = "Brightness", speed = "Speed", tau = "Tau", phi = "Phi"
    case primary = "Primary color", secondary = "Secondary color"
    var id: Self { self }

    init(_ target: KnobTarget) {
        switch target {
        case .brightness: self = .brightness
        case .speed: self = .speed
        case .tau: self = .tau
        case .phi: self = .phi
        case .color(.primary, _): self = .primary
        case .color(.secondary, _): self = .secondary
        }
    }

    var isLayer: Bool { self != .brightness }
    var isColor: Bool { self == .primary || self == .secondary }

    func target(_ channel: KnobTarget.ColorChannel) -> KnobTarget {
        switch self {
        case .brightness: .brightness
        case .speed: .speed
        case .tau: .tau
        case .phi: .phi
        case .primary: .color(.primary, channel)
        case .secondary: .color(.secondary, channel)
        }
    }

    func targets(in docs: WiringDocs) -> [KnobTarget] { docs.targets.filter { KnobParam($0) == self } }
}

extension KnobTarget.ColorChannel {
    var shortName: String {
        switch self {
        case .red: "R"
        case .green: "G"
        case .blue: "B"
        case .hue: "Hue"
        case .saturation: "Sat"
        case .value: "Val"
        }
    }

    var name: String {
        switch self {
        case .red: "red"
        case .green: "green"
        case .blue: "blue"
        case .hue: "hue"
        case .saturation: "saturation"
        case .value: "value"
        }
    }
}

extension KnobTarget {
    var name: String {
        switch self {
        case .brightness: "Brightness"
        case .speed: "Speed"
        case .tau: "Tau"
        case .phi: "Phi"
        case .color(let slot, let channel): "\(slot == .primary ? "primary" : "secondary") \(channel.name)"
        }
    }

    var defaultRange: ClosedRange<Double> {
        switch self {
        case .brightness, .color: 0 ... 255
        case .speed: 0.1 ... 10
        case .tau, .phi: 0.5 ... 20
        }
    }

    /// The editor's slider: the Animation tab's log ranges for speed, tau and phi; 0-255 otherwise.
    private var sliderRange: ClosedRange<Double> {
        switch self {
        case .brightness, .color: 0 ... 255
        case .speed: 0.01 ... 60
        case .tau, .phi: 0.01 ... 80
        }
    }

    private var isLogarithmic: Bool { self == .speed || self == .tau || self == .phi }

    func sliderFraction(of value: Double) -> Double {
        let r = sliderRange
        let f = isLogarithmic
            ? log(Swift.max(value, r.lowerBound) / r.lowerBound) / log(r.upperBound / r.lowerBound)
            : (value - r.lowerBound) / (r.upperBound - r.lowerBound)
        return Swift.min(Swift.max(f, 0), 1)
    }

    /// Rounded to whole steps of 0-255, or two significant digits on log scales, to keep `wiring` short.
    func value(atSliderFraction f: Double) -> Double {
        let r = sliderRange
        guard isLogarithmic else { return (r.lowerBound + f * (r.upperBound - r.lowerBound)).rounded() }
        let value = r.lowerBound * pow(r.upperBound / r.lowerBound, f)
        return Double(String(format: "%.2g", value)) ?? value
    }

    func format(_ value: Double) -> String {
        switch self {
        case .brightness: "\(Int(value.rounded()))"
        case .speed: String(format: "%.2g s", value)
        case .tau, .phi: String(format: "%.2g", value)
        case .color(_, .hue): "\(Int((value / 255 * 360).rounded()))°"
        case .color(_, .saturation), .color(_, .value): "\(Int((value / 255 * 100).rounded()))%"
        case .color: "\(Int(value.rounded()))"
        }
    }

    /// The value that a knob from `min` to `max` writes at `position` (0-1),
    /// following the firmware's curves: square law for brightness,
    /// logarithmic for speed, tau and phi when both ends are positive.
    func knobValue(min: Double, max: Double, position p: Double) -> Double {
        if self == .brightness { return min + (max - min) * p * p }
        if isLogarithmic, min > 0, max > 0 { return min * pow(max / min, p) }
        return min + (max - min) * p
    }
}

// MARK: - Range slider

/// Two handles on a 0-1 track, with an optional marker for the knob's live position.
struct RangeSliderView: View {
    @Binding var range: ClosedRange<Double>
    let live: Double?
    /// Formats a fraction's value for VoiceOver.
    let describe: (Double) -> String
    let onEnded: () -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width - 28
            let lo = 14 + w * range.lowerBound
            let hi = 14 + w * range.upperBound
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.25)).frame(height: 6).padding(.horizontal, 14)
                Capsule().fill(Color.accentColor).frame(width: max(hi - lo, 0), height: 6).offset(x: lo)
                if let live {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .position(x: 14 + w * live, y: 6)
                        .accessibilityHidden(true)
                }
                thumb(label: "Low end", fraction: range.lowerBound) { range = min(max($0, 0), range.upperBound) ... range.upperBound }
                    .position(x: lo, y: geo.size.height / 2)
                    .gesture(DragGesture()
                        .onChanged { v in range = min(max((v.location.x - 14) / w, 0), range.upperBound) ... range.upperBound }
                        .onEnded { _ in onEnded() })
                thumb(label: "High end", fraction: range.upperBound) { range = range.lowerBound ... max(min($0, 1), range.lowerBound) }
                    .position(x: hi, y: geo.size.height / 2)
                    .gesture(DragGesture()
                        .onChanged { v in range = range.lowerBound ... max(min((v.location.x - 14) / w, 1), range.lowerBound) }
                        .onEnded { _ in onEnded() })
            }
        }
    }

    private func thumb(label: String, fraction: Double, set: @escaping (Double) -> Void) -> some View {
        Circle()
            .fill(.white)
            .shadow(radius: 2, y: 1)
            .frame(width: 26, height: 26)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(describe(fraction))
            .accessibilityAdjustableAction { direction in
                set(fraction + (direction == .increment ? 0.05 : -0.05))
                onEnded()
            }
    }
}

// MARK: - Previews

/// Runs a demo session and opens the editor once wiring has loaded.
private struct EditorPreview: View {
    let pin: String
    @State private var session: CoreSession

    init(board: FakeCoreLink.DemoBoard, pin: String, edit: (inout Wiring) -> Void = { _ in }) {
        let link = FakeCoreLink.demo(board: board)
        if var wiring = link.values[CoreProps.wiring.id].flatMap(WiringConverter.convert) {
            edit(&wiring)
            link.values[CoreProps.wiring.id] = wiring.json
        }
        self.pin = pin
        _session = State(initialValue: CoreSession(link: link))
    }

    var body: some View {
        Group {
            if let docs = session.state.wiringDocs, session.state[CoreProps.wiring] != nil {
                PinEditorView(session: session, pin: pin, docs: docs)
            } else {
                ProgressView()
            }
        }
        .task { await session.run() }
    }
}

#Preview("Knob on G32, Echo") { EditorPreview(board: .atomEcho, pin: "G32") }
#Preview("Hue knob on G33, Lite") { EditorPreview(board: .atomLite, pin: "G33") }
#Preview("Switch on G22, Lite") { EditorPreview(board: .atomLite, pin: "G22") }
#Preview("Button on G21, Echo") { EditorPreview(board: .atomEcho, pin: "G21") }
#Preview("Front button, unset, Echo") { EditorPreview(board: .atomEcho, pin: "G39") { $0["G39"] = nil } }
#Preview("LEDs on G1, S3") { EditorPreview(board: .atomS3Lite, pin: "G1") }
#Preview("Nothing on G8, S3") { EditorPreview(board: .atomS3Lite, pin: "G8") { $0["G8"] = nil } }
