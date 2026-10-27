import SwiftUI

// UI prototype for the Wiring tab. Fake data only; the protocol is designed from this.

// MARK: - Model stand-ins

enum ProtoKind: String, CaseIterable, Identifiable {
    case nothing = "Nothing", toggle = "Switch", button = "Button", knob = "Knob", leds = "LEDs"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .nothing: "circle.dashed"
        case .toggle: "switch.2"
        case .button: "button.programmable"
        case .knob: "dial.medium"
        case .leds: "lightbulb.led"
        }
    }
    var tint: Color {
        switch self {
        case .nothing: .gray
        case .toggle: .blue
        case .button: .purple
        case .knob: .orange
        case .leds: .pink
        }
    }
}

enum ProtoSwitchAction: String, CaseIterable, Identifiable {
    case lightsOff = "Lights off", lightsOn = "Lights on", preset = "Preset", layer = "Layer on"
    var id: Self { self }
}

enum ProtoButtonAction: String, CaseIterable, Identifiable {
    case nextPreset = "Next preset", toggleLights = "Lights on/off", preset = "Preset", toggleLayer = "Layer on/off"
    var id: Self { self }
}

enum ProtoKnobParam: String, CaseIterable, Identifiable {
    case brightness = "Brightness", speed = "Speed", tau = "Tau", phi = "Phi"
    case primary = "Primary color", secondary = "Secondary color"
    var id: Self { self }
    var isLayer: Bool { self != .brightness }
    var isColor: Bool { self == .primary || self == .secondary }
    /// Default knob range as fractions of the target's own scale.
    var defaultRange: ClosedRange<Double> {
        switch self {
        case .speed: 0.265 ... 0.794 // 0.1 s ... 10 s on the log scale
        case .tau, .phi: 0.25 ... 0.75
        default: 0 ... 1
        }
    }
}

enum ProtoChannel: String, CaseIterable, Identifiable {
    case red = "R", green = "G", blue = "B", hue = "Hue", saturation = "Sat", value = "Val"
    var id: Self { self }
}

struct ProtoBinding: Equatable {
    var kind: ProtoKind = .nothing
    var switchAction: ProtoSwitchAction = .lightsOff
    var buttonAction: ProtoButtonAction = .nextPreset
    var knobParam: ProtoKnobParam = .brightness
    var channel: ProtoChannel = .hue
    var index = 0
    var range: ClosedRange<Double> = 0 ... 1
    var reversed = false

    var summary: String {
        switch kind {
        case .nothing: return "Not used"
        case .leds: return "LED strip data"
        case .toggle:
            switch switchAction {
            case .lightsOff: return "Closed: lights off"
            case .lightsOn: return "Closed: lights on"
            case .preset: return "Closed: preset \(index)"
            case .layer: return "Closed: layer \(index) on"
            }
        case .button:
            switch buttonAction {
            case .nextPreset: return "Next preset · hold: lights on/off"
            case .toggleLights: return "Lights on/off"
            case .preset: return "Preset \(index)"
            case .toggleLayer: return "Layer \(index) on/off"
            }
        case .knob:
            if !knobParam.isLayer { return knobParam.rawValue }
            if knobParam.isColor {
                return "Layer \(index) · \(knobParam == .primary ? "primary" : "secondary") \(channelName)"
            }
            return "Layer \(index) · \(knobParam.rawValue)"
        }
    }

    var channelName: String {
        switch channel {
        case .red: "red"
        case .green: "green"
        case .blue: "blue"
        case .hue: "hue"
        case .saturation: "saturation"
        case .value: "value"
        }
    }

    func format(_ f: Double) -> String {
        switch knobParam {
        case .brightness: return "\(Int((f * 255).rounded()))"
        case .speed: return String(format: "%.2g s", 0.01 * pow(6000, f))
        case .tau, .phi: return String(format: "%.2g", 0.01 * pow(8000, f))
        case .primary, .secondary:
            switch channel {
            case .hue: return "\(Int((f * 360).rounded()))°"
            case .saturation, .value: return "\(Int((f * 100).rounded()))%"
            default: return "\(Int((f * 255).rounded()))"
            }
        }
    }
}

struct ProtoPin: Identifiable, Equatable {
    let id: String
    var analog = false
    var led = false
    var claim: String? = nil
    var binding = ProtoBinding()
    var closed = false
    var position = 0.0

    var roles: [ProtoKind] {
        ProtoKind.allCases.filter { ($0 != .knob || analog) && ($0 != .leds || led) }
    }
}

/// Pin labels as printed on the case.
struct ProtoBoard {
    let name: String
    let leftHeader: [String]   // top to bottom, Grove port facing down
    let rightHeader: [String]
    let grove: [String]        // black, red, yellow, white
    let analogPins: [String]
    static let groveColors: [Color] = [.black, .red, .yellow, .white]
    static let groveColorNames = ["black", "red", "yellow", "white"]

    static let atomLite = ProtoBoard(
        name: "Atom Lite",
        leftHeader: ["3V3", "G22", "G19", "G23", "G33"],
        rightHeader: ["G21", "G25", "5V", "G"],
        grove: ["G", "5V", "G26", "G32"],
        analogPins: ["G33", "G32"])
    static let atomEcho = ProtoBoard(
        name: "Atom Echo",
        leftHeader: ["3V3", "G22", "G19", "G23", "G33"],
        rightHeader: ["G21", "G25", "5V", "G"],
        grove: ["G", "5V", "G26", "G32"],
        analogPins: ["G32"])
    static let atomS3Lite = ProtoBoard(
        name: "AtomS3 Lite",
        leftHeader: ["3V3", "G5", "G6", "G7", "G8"],
        rightHeader: ["G39", "G38", "5V", "G"],
        grove: ["G", "5V", "G2", "G1"],
        analogPins: ["G5", "G6", "G7", "G8", "G2", "G1"])

    func isGroveSignal(_ label: String) -> Bool { grove.dropFirst(2).contains(label) }

    func location(of label: String, grove onGrove: Bool) -> String {
        if onGrove, let i = grove.firstIndex(of: label) {
            let wire = "the \(Self.groveColorNames[i]) wire of the Grove cable"
            return isGroveSignal(label) ? "\(wire) (\(label))" : wire
        }
        return label == "G" ? "G (ground) on the back header" : "\(label) on the back header"
    }
}

// MARK: - Wiring tab

struct WiringPrototypeView: View {
    let board: ProtoBoard
    @State var pins: [ProtoPin]
    @State private var editing: EditTarget?

    struct EditTarget: Identifiable { let id: String }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                BoardFaceView(board: board, emphasis: emphasis)
                    .frame(height: 200)
                VStack(spacing: 0) {
                    ForEach(pins) { pin in
                        PinRow(pin: pin)
                            .contentShape(Rectangle())
                            .onTapGesture { if pin.claim == nil { editing = EditTarget(id: pin.id) } }
                        if pin.id != pins.last?.id { Divider().padding(.leading, 64) }
                    }
                }
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                Text("Wiggle a switch or turn a knob to see which row reacts. Wiring is the same in every preset.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .sheet(item: $editing) { target in
            if let i = pins.firstIndex(where: { $0.id == target.id }) {
                PinEditorView(board: board, pin: $pins[i],
                              contextLED: pins.first { $0.binding.kind == .leds && $0.id != target.id }?.id)
            }
        }
    }

    private var emphasis: [String: Color] {
        var e: [String: Color] = [:]
        for pin in pins where pin.binding.kind != .nothing { e[pin.id] = pin.binding.kind.tint }
        return e
    }
}

struct PinRow: View {
    let pin: ProtoPin

    var body: some View {
        HStack(spacing: 12) {
            Text(pin.id)
                .font(.system(.subheadline, design: .monospaced).bold())
                .foregroundStyle(pin.claim == nil ? .white : .secondary)
                .frame(width: 44, height: 28)
                .background(pin.claim == nil ? pin.binding.kind.tint : Color.gray.opacity(0.25),
                            in: RoundedRectangle(cornerRadius: 6))
            if let claim = pin.claim {
                Text("Used by \(claim)").foregroundStyle(.secondary)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Label(pin.binding.kind.rawValue, systemImage: pin.binding.kind.symbol)
                        .font(.headline)
                    Text(pin.binding.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                LiveIndicator(pin: pin)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct LiveIndicator: View {
    let pin: ProtoPin

    var body: some View {
        switch pin.binding.kind {
        case .leds:
            EmptyView()
        case .knob:
            positionBar
        case .nothing where pin.analog:
            positionBar
        default:
            VStack(spacing: 2) {
                Circle()
                    .fill(pin.closed ? Color.green : Color.clear)
                    .stroke(pin.closed ? Color.green : Color.gray, lineWidth: 2)
                    .frame(width: 14, height: 14)
                Text(pin.closed ? "closed" : "open")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var positionBar: some View {
        Capsule()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 56, height: 8)
            .overlay(alignment: .leading) {
                Capsule().fill(Color.orange).frame(width: 56 * pin.position, height: 8)
            }
    }
}

// MARK: - Editor

struct PinEditorView: View {
    let board: ProtoBoard
    @Binding var pin: ProtoPin
    var contextLED: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Wired", selection: $pin.binding.kind) {
                        ForEach(pin.roles) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("What's wired to \(pin.id)?")
                } footer: {
                    if !pin.analog {
                        Text("Knobs only work on \(board.analogPins.joined(separator: ", ")) on the \(board.name).")
                    }
                }

                if pin.binding.kind != .nothing {
                    Section("How to wire it") {
                        WiringDiagramView(board: board, pin: pin.id, kind: pin.binding.kind, contextLED: contextLED)
                            .frame(height: 340)
                            .listRowInsets(EdgeInsets())
                        WiringSteps(board: board, pin: pin.id, kind: pin.binding.kind)
                    }
                }

                switch pin.binding.kind {
                case .nothing: EmptyView()
                case .leds: ledSection
                case .toggle: switchSection
                case .button: buttonSection
                case .knob: knobSections
                }
            }
            .navigationTitle(pin.id)
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private var indexPicker: some View {
        let isPreset = pin.binding.kind == .toggle ? pin.binding.switchAction == .preset : pin.binding.buttonAction == .preset
        return Picker(isPreset ? "Preset" : "Layer", selection: $pin.binding.index) {
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

    @ViewBuilder private var switchSection: some View {
        Section {
            Picker("When closed", selection: $pin.binding.switchAction) {
                ForEach(ProtoSwitchAction.allCases) { Text($0.rawValue).tag($0) }
            }
            if pin.binding.switchAction == .preset || pin.binding.switchAction == .layer { indexPicker }
        } footer: {
            Text("While the switch is closed it holds this, and the app can't change it.")
        }
    }

    @ViewBuilder private var buttonSection: some View {
        Section {
            Picker("When pressed", selection: $pin.binding.buttonAction) {
                ForEach(ProtoButtonAction.allCases) { Text($0.rawValue).tag($0) }
            }
            if pin.binding.buttonAction == .preset || pin.binding.buttonAction == .toggleLayer { indexPicker }
        } footer: {
            if pin.binding.buttonAction == .nextPreset {
                Text("Hold for half a second to turn the lights on or off.")
            }
        }
    }

    @ViewBuilder private var knobSections: some View {
        Section("Controls") {
            Picker("Target", selection: $pin.binding.knobParam) {
                ForEach(ProtoKnobParam.allCases) { Text($0.rawValue).tag($0) }
            }
            .onChange(of: pin.binding.knobParam) { _, param in pin.binding.range = param.defaultRange }
            if pin.binding.knobParam.isLayer {
                Picker("Layer", selection: $pin.binding.index) {
                    ForEach(0 ..< 10, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if pin.binding.knobParam.isColor {
                Picker("Channel", selection: $pin.binding.channel) {
                    ForEach(ProtoChannel.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        Section {
            RangeSliderView(range: $pin.binding.range, live: pin.position, reversed: pin.binding.reversed)
                .frame(height: 44)
            HStack {
                Text(pin.binding.format(pin.binding.reversed ? pin.binding.range.upperBound : pin.binding.range.lowerBound))
                Spacer()
                Text("now \(pin.binding.format(liveValue))").foregroundStyle(.orange)
                Spacer()
                Text(pin.binding.format(pin.binding.reversed ? pin.binding.range.lowerBound : pin.binding.range.upperBound))
            }
            .font(.subheadline.monospacedDigit())
            Toggle("Reverse", isOn: $pin.binding.reversed)
        } header: {
            Text("Range")
        } footer: {
            Text("Knob fully left to fully right sweeps between the two handles.")
        }
    }

    private var liveValue: Double {
        let r = pin.binding.range
        let p = pin.binding.reversed ? 1 - pin.position : pin.position
        return r.lowerBound + p * (r.upperBound - r.lowerBound)
    }
}

struct RangeSliderView: View {
    @Binding var range: ClosedRange<Double>
    let live: Double
    let reversed: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width - 28
            let lo = 14 + w * range.lowerBound
            let hi = 14 + w * range.upperBound
            let p = reversed ? 1 - live : live
            let marker = lo + (hi - lo) * p
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.25)).frame(height: 6).padding(.horizontal, 14)
                Capsule().fill(Color.accentColor).frame(width: max(hi - lo, 0), height: 6).offset(x: lo)
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .position(x: marker, y: 6)
                thumb.position(x: lo, y: geo.size.height / 2)
                    .gesture(DragGesture().onChanged { v in
                        range = min(max((v.location.x - 14) / w, 0), range.upperBound) ... range.upperBound
                    })
                thumb.position(x: hi, y: geo.size.height / 2)
                    .gesture(DragGesture().onChanged { v in
                        range = range.lowerBound ... max(min((v.location.x - 14) / w, 1), range.lowerBound)
                    })
            }
        }
    }

    private var thumb: some View {
        Circle()
            .fill(.white)
            .shadow(radius: 2, y: 1)
            .frame(width: 26, height: 26)
    }
}

// MARK: - Board and wiring drawings

struct BoardGeometry {
    let board: ProtoBoard
    let origin: CGPoint
    let size: CGFloat = 140
    var rect: CGRect { CGRect(origin: origin, size: CGSize(width: size, height: size)) }

    func hole(_ label: String) -> (point: CGPoint, outward: CGFloat)? {
        if let i = board.leftHeader.firstIndex(of: label) {
            return (CGPoint(x: origin.x + 12, y: origin.y + 30 + CGFloat(i) * 20), -1)
        }
        if let i = board.rightHeader.firstIndex(of: label) {
            return (CGPoint(x: origin.x + size - 12, y: origin.y + 30 + CGFloat(i) * 20), 1)
        }
        return nil
    }

    func groveX(_ i: Int) -> CGFloat { origin.x + 40 + CGFloat(i) * 20 }
    var groveY: CGFloat { origin.y + size + 4 }
}

private func roundedPolyline(_ pts: [CGPoint], radius: CGFloat = 8) -> Path {
    var p = Path()
    guard let first = pts.first, let last = pts.last else { return p }
    p.move(to: first)
    if pts.count > 2 {
        for i in 1 ..< pts.count - 1 {
            p.addArc(tangent1End: pts[i], tangent2End: pts[i + 1], radius: radius)
        }
    }
    p.addLine(to: last)
    return p
}

private func strokeWire(_ ctx: GraphicsContext, _ path: Path, _ color: Color, faded: Bool = false) {
    var c = ctx
    if faded { c.opacity = 0.3 }
    let outline: Color = color == .black ? Color(white: 0.55) : .black.opacity(0.6)
    c.stroke(path, with: .color(outline), style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
    c.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
}

private func label(_ s: String, bold: Bool = false, color: Color = .primary, size: CGFloat = 9) -> Text {
    Text(s).font(.system(size: size, weight: bold ? .bold : .regular, design: .monospaced)).foregroundColor(color)
}

/// Draws the board seen from the back: headers left and right, the Grove socket at the bottom.
private func drawBoard(_ ctx: GraphicsContext, _ g: BoardGeometry, emphasis: [String: Color]) {
    let body = Path(roundedRect: g.rect, cornerRadius: 18)
    ctx.fill(body, with: .color(Color(white: 0.92)))
    ctx.stroke(body, with: .color(Color(white: 0.6)), lineWidth: 1)
    let center = CGPoint(x: g.rect.midX, y: g.rect.midY - 6)
    ctx.draw(label("ATOM", bold: true, color: .gray, size: 13), at: center)
    ctx.draw(label(g.board.name, color: .gray, size: 8), at: CGPoint(x: center.x, y: center.y + 14))

    for (header, x) in [(g.board.leftHeader, g.origin.x + 12), (g.board.rightHeader, g.origin.x + g.size - 12)] {
        let strip = CGRect(x: x - 7, y: g.origin.y + 20, width: 14, height: CGFloat(header.count) * 20)
        ctx.fill(Path(roundedRect: strip, cornerRadius: 3), with: .color(.black))
        for name in header {
            guard let (p, out) = g.hole(name) else { continue }
            let hole = CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
            ctx.fill(Path(hole), with: .color(Color(white: 0.35)))
            let tint = emphasis[name]
            if let tint {
                ctx.stroke(Path(ellipseIn: hole.insetBy(dx: -3, dy: -3)), with: .color(tint), lineWidth: 2)
            }
            ctx.draw(label(name, bold: tint != nil, color: tint ?? .secondary),
                     at: CGPoint(x: p.x - out * 12, y: p.y), anchor: out < 0 ? .leading : .trailing)
        }
    }

    let socket = CGRect(x: g.groveX(0) - 10, y: g.rect.maxY - 12, width: 80, height: 16)
    ctx.fill(Path(roundedRect: socket, cornerRadius: 2), with: .color(.white))
    ctx.stroke(Path(roundedRect: socket, cornerRadius: 2), with: .color(.gray), lineWidth: 1)
    ctx.draw(label("Grove", color: .secondary, size: 8), at: CGPoint(x: socket.midX, y: socket.minY - 8))
}

struct BoardFaceView: View {
    let board: ProtoBoard
    let emphasis: [String: Color]

    var body: some View {
        Canvas { ctx, size in
            let g = BoardGeometry(board: board, origin: CGPoint(x: (size.width - 140) / 2, y: 8))
            for (i, name) in board.grove.enumerated() {
                let x = g.groveX(i)
                let path = roundedPolyline([CGPoint(x: x, y: g.groveY - 4), CGPoint(x: x, y: g.groveY + 30)])
                let signal = board.isGroveSignal(name)
                strokeWire(ctx, path, ProtoBoard.groveColors[i], faded: signal && emphasis[name] == nil)
                let tint = signal ? emphasis[name] : nil
                ctx.draw(label(name, bold: tint != nil, color: tint ?? .secondary, size: 8),
                         at: CGPoint(x: x, y: g.groveY + 40))
            }
            drawBoard(ctx, g, emphasis: emphasis.filter { !board.isGroveSignal($0.key) })
        }
    }
}

/// One wire from a board pin to a component leg.
private struct ProtoWire {
    let from: String
    let grove: Bool
    let leg: Int
    let legName: String
}

private func wires(for kind: ProtoKind, pin: String, on board: ProtoBoard) -> [ProtoWire] {
    let pinOnGrove = board.isGroveSignal(pin)
    switch kind {
    case .knob:
        return [ProtoWire(from: "G", grove: false, leg: 0, legName: "One outer leg"),
                ProtoWire(from: pin, grove: pinOnGrove, leg: 1, legName: "Middle leg"),
                ProtoWire(from: "3V3", grove: false, leg: 2, legName: "Other outer leg")]
    case .toggle, .button:
        return [ProtoWire(from: pin, grove: pinOnGrove, leg: 0, legName: "One leg"),
                ProtoWire(from: "G", grove: false, leg: 1, legName: "Other leg")]
    case .leds:
        return [ProtoWire(from: "G", grove: true, leg: 0, legName: "The strip's G (or GND)"),
                ProtoWire(from: pin, grove: true, leg: 1, legName: "The strip's DIN"),
                ProtoWire(from: "5V", grove: true, leg: 2, legName: "The strip's 5V")]
    case .nothing:
        return []
    }
}

struct WiringDiagramView: View {
    let board: ProtoBoard
    let pin: String
    let kind: ProtoKind
    var contextLED: String? = nil

    var body: some View {
        Canvas { ctx, size in
            let g = BoardGeometry(board: board, origin: CGPoint(x: (size.width - 140) / 2 - 20, y: 14))
            let ws = wires(for: kind, pin: pin, on: board)
            let legTipY: CGFloat = 268
            let cx = size.width - 80
            let legXs: [CGFloat] = kind == .toggle || kind == .button ? [cx - 14, cx + 14] : [cx - 24, cx, cx + 24]
            var groveUsed = Set(ws.filter(\.grove).map(\.from))

            // An already-wired LED strip, faded, so the new wires have something to orient by.
            if kind != .leds, let led = contextLED, let di = board.grove.firstIndex(of: led) {
                let stripPads: [CGFloat] = [40, 60, 80]
                for (n, gi) in [0, 1, di].enumerated() {
                    let x = g.groveX(gi)
                    let laneY = g.groveY + 18 + CGFloat(n) * 7
                    strokeWire(ctx, roundedPolyline([
                        CGPoint(x: x, y: g.groveY - 4), CGPoint(x: x, y: laneY),
                        CGPoint(x: stripPads[n], y: laneY), CGPoint(x: stripPads[n], y: 300),
                    ]), ProtoBoard.groveColors[gi], faded: true)
                    groveUsed.insert(board.grove[gi])
                }
                let strip = CGRect(x: 28, y: 300, width: 64, height: 18)
                ctx.fill(Path(roundedRect: strip, cornerRadius: 3), with: .color(Color(white: 0.85)))
                ctx.draw(label("LED strip", color: .secondary, size: 8), at: CGPoint(x: strip.midX, y: strip.midY))
            }
            for (gi, name) in board.grove.enumerated() where !groveUsed.contains(name) {
                let x = g.groveX(gi)
                strokeWire(ctx, roundedPolyline([CGPoint(x: x, y: g.groveY - 4), CGPoint(x: x, y: g.groveY + 14)]),
                           ProtoBoard.groveColors[gi], faded: true)
            }

            var used: [String: Color] = [:]
            for (n, w) in ws.enumerated() {
                let legTip = CGPoint(x: legXs[w.leg], y: legTipY)
                let laneY = legTipY - 22 - CGFloat(n) * 9
                var pts: [CGPoint]
                var color: Color
                if w.grove, let gi = board.grove.firstIndex(of: w.from) {
                    let x = g.groveX(gi)
                    pts = [CGPoint(x: x, y: g.groveY - 4), CGPoint(x: x, y: laneY), CGPoint(x: legTip.x, y: laneY), legTip]
                    color = ProtoBoard.groveColors[gi]
                } else if let (p, out) = g.hole(w.from) {
                    let outX = out < 0 ? g.rect.minX - 14 - CGFloat(n) * 8 : g.rect.maxX + 14 + CGFloat(n) * 8
                    pts = [p, CGPoint(x: outX, y: p.y), CGPoint(x: outX, y: laneY), CGPoint(x: legTip.x, y: laneY), legTip]
                    color = w.from == "3V3" ? .orange : w.from == "G" ? Color(white: 0.2) : .green
                    used[w.from] = color
                } else { continue }
                strokeWire(ctx, roundedPolyline(pts), color)
            }
            drawBoard(ctx, g, emphasis: used)

            switch kind {
            case .knob: drawPot(ctx, cx: cx, legTipY: legTipY, legXs: legXs)
            case .toggle: drawSwitch(ctx, cx: cx, legTipY: legTipY, legXs: legXs)
            case .button: drawButton(ctx, cx: cx, legTipY: legTipY, legXs: legXs)
            case .leds: drawStrip(ctx, cx: cx, legTipY: legTipY, legXs: legXs)
            case .nothing: break
            }
        }
    }

    private func drawLegs(_ ctx: GraphicsContext, _ legXs: [CGFloat], _ tipY: CGFloat) {
        for x in legXs {
            ctx.fill(Path(CGRect(x: x - 3, y: tipY, width: 6, height: 22)), with: .color(Color(white: 0.7)))
            ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: tipY - 4, width: 8, height: 8)), with: .color(Color(white: 0.8)))
        }
    }

    private func drawPot(_ ctx: GraphicsContext, cx: CGFloat, legTipY: CGFloat, legXs: [CGFloat]) {
        drawLegs(ctx, legXs, legTipY)
        let body = CGRect(x: cx - 40, y: legTipY + 22, width: 80, height: 50)
        ctx.fill(Path(roundedRect: body, cornerRadius: 6), with: .color(Color(white: 0.3)))
        let c = CGPoint(x: cx, y: body.midY)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 18, y: c.y - 18, width: 36, height: 36)), with: .color(Color(white: 0.7)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 13, y: c.y - 13, width: 26, height: 26)), with: .color(Color(white: 0.85)))
        var tick = Path()
        tick.move(to: c)
        tick.addLine(to: CGPoint(x: c.x + 9, y: c.y - 9))
        ctx.stroke(tick, with: .color(.black), lineWidth: 2)
    }

    private func drawSwitch(_ ctx: GraphicsContext, cx: CGFloat, legTipY: CGFloat, legXs: [CGFloat]) {
        drawLegs(ctx, legXs, legTipY)
        let body = CGRect(x: cx - 32, y: legTipY + 22, width: 64, height: 34)
        var lever = Path(roundedRect: CGRect(x: cx - 4, y: body.maxY - 4, width: 8, height: 26), cornerRadius: 4)
        lever = lever.applying(CGAffineTransform(translationX: cx, y: body.maxY).rotated(by: -0.4).translatedBy(x: -cx, y: -body.maxY))
        ctx.fill(lever, with: .color(Color(white: 0.75)))
        ctx.fill(Path(roundedRect: body, cornerRadius: 5), with: .color(Color(white: 0.25)))
    }

    private func drawButton(_ ctx: GraphicsContext, cx: CGFloat, legTipY: CGFloat, legXs: [CGFloat]) {
        drawLegs(ctx, legXs, legTipY)
        let body = CGRect(x: cx - 24, y: legTipY + 22, width: 48, height: 44)
        ctx.fill(Path(roundedRect: body, cornerRadius: 4), with: .color(Color(white: 0.25)))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 14, y: body.midY - 14, width: 28, height: 28)), with: .color(.red))
    }

    private func drawStrip(_ ctx: GraphicsContext, cx: CGFloat, legTipY: CGFloat, legXs: [CGFloat]) {
        let body = CGRect(x: cx - 46, y: legTipY + 8, width: 92, height: 50)
        ctx.fill(Path(roundedRect: body, cornerRadius: 3), with: .color(Color(white: 0.97)))
        ctx.stroke(Path(roundedRect: body, cornerRadius: 3), with: .color(.gray), lineWidth: 1)
        for i in 0 ..< 3 {
            let led = CGRect(x: body.minX + 10 + CGFloat(i) * 30, y: body.midY + 2, width: 14, height: 14)
            ctx.fill(Path(roundedRect: led, cornerRadius: 2), with: .color(Color(white: 0.9)))
            ctx.stroke(Path(roundedRect: led, cornerRadius: 2), with: .color(Color(white: 0.6)), lineWidth: 1)
        }
        ctx.draw(label("→ → →", bold: true, color: .pink, size: 10), at: CGPoint(x: body.midX, y: body.maxY + 10))
        for (x, name) in zip(legXs, ["G", "DIN", "5V"]) {
            ctx.fill(Path(roundedRect: CGRect(x: x - 7, y: legTipY - 2, width: 14, height: 10), cornerRadius: 2),
                     with: .color(Color(red: 0.85, green: 0.65, blue: 0.3)))
            ctx.draw(label(name, size: 7), at: CGPoint(x: x, y: legTipY + 16))
        }
    }

}

struct WiringSteps: View {
    let board: ProtoBoard
    let pin: String
    let kind: ProtoKind

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(wires(for: kind, pin: pin, on: board).enumerated()), id: \.offset) { n, w in
                Text("\(n + 1). \(w.legName) → \(board.location(of: w.from, grove: w.grove)).")
            }
            switch kind {
            case .knob:
                Label("Use 3V3, never the red 5V wire: more than 3.3 V on \(pin) can damage the \(board.name).",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Turns the wrong way? Swap the outer legs, or tap Reverse below.")
                    .foregroundStyle(.secondary)
            case .leds:
                Text("Connect the end where the strip's arrows point away from the Atom; the other end won't light up.")
                    .foregroundStyle(.secondary)
            default:
                Text("Any \(kind == .button ? "push button" : "on/off switch") works; which leg is which doesn't matter.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }
}

// MARK: - Previews

extension ProtoPin {
    static func echoDemo(position: Double = 0.62) -> [ProtoPin] {
        [
            ProtoPin(id: "G26", led: true, binding: ProtoBinding(kind: .leds)),
            ProtoPin(id: "G32", analog: true, led: true, binding: ProtoBinding(kind: .knob), position: position),
            ProtoPin(id: "G25", binding: ProtoBinding(kind: .toggle)),
            ProtoPin(id: "G21", binding: ProtoBinding(kind: .button), closed: true),
            ProtoPin(id: "G19", claim: "the speaker"),
            ProtoPin(id: "G22", claim: "the speaker"),
            ProtoPin(id: "G23", claim: "the microphone"),
            ProtoPin(id: "G33", claim: "the microphone"),
        ]
    }

    static let liteDemo: [ProtoPin] = [
        ProtoPin(id: "G26", led: true, binding: ProtoBinding(kind: .leds)),
        ProtoPin(id: "G32", analog: true, led: true, binding: ProtoBinding(kind: .leds)),
        ProtoPin(id: "G33", analog: true,
                 binding: ProtoBinding(kind: .knob, knobParam: .primary, channel: .hue, index: 2), position: 0.3),
        ProtoPin(id: "G25", binding: ProtoBinding(kind: .toggle)),
        ProtoPin(id: "G21", binding: ProtoBinding(kind: .button)),
        ProtoPin(id: "G22", binding: ProtoBinding(kind: .toggle, switchAction: .preset, index: 0), closed: true),
        ProtoPin(id: "G19", binding: ProtoBinding(kind: .toggle, switchAction: .preset, index: 1)),
        ProtoPin(id: "G23", binding: ProtoBinding(kind: .toggle, switchAction: .preset, index: 2)),
    ]

    static let s3Demo: [ProtoPin] = [
        ProtoPin(id: "G2", analog: true, led: true, binding: ProtoBinding(kind: .leds)),
        ProtoPin(id: "G1", analog: true, led: true, binding: ProtoBinding(kind: .leds)),
        ProtoPin(id: "G38", binding: ProtoBinding(kind: .toggle)),
        ProtoPin(id: "G39", binding: ProtoBinding(kind: .button)),
        ProtoPin(id: "G5", analog: true, binding: ProtoBinding(kind: .toggle, switchAction: .preset, index: 0)),
        ProtoPin(id: "G6", analog: true, binding: ProtoBinding(kind: .toggle, switchAction: .preset, index: 1)),
        ProtoPin(id: "G7", analog: true, binding: ProtoBinding(kind: .toggle, switchAction: .preset, index: 2)),
        ProtoPin(id: "G8", analog: true, binding: ProtoBinding(kind: .toggle, switchAction: .preset, index: 3)),
    ]
}

private struct TabMock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        TabView(selection: .constant(3)) {
            Text("Animation").tabItem { Label("Animation", systemImage: "sparkles") }.tag(0)
            Text("Core").tabItem { Label("Core", systemImage: "gearshape") }.tag(1)
            Text("Mesh").tabItem { Label("Mesh", systemImage: "antenna.radiowaves.left.and.right") }.tag(2)
            NavigationStack { content.navigationTitle(title) }
                .tabItem { Label("Wiring", systemImage: "cable.connector") }.tag(3)
        }
    }
}

#Preview("Wiring, Atom Echo") {
    TabMock(title: "Gustav") { WiringPrototypeView(board: .atomEcho, pins: ProtoPin.echoDemo()) }
}

#Preview("Wiring, Atom Lite") {
    TabMock(title: "Vindarnas hus") { WiringPrototypeView(board: .atomLite, pins: ProtoPin.liteDemo) }
}

#Preview("Wiring, AtomS3 Lite") {
    TabMock(title: "Nevyn") { WiringPrototypeView(board: .atomS3Lite, pins: ProtoPin.s3Demo) }
}

#Preview("Knob on G32, Echo") {
    @Previewable @State var pin = ProtoPin.echoDemo()[1]
    PinEditorView(board: .atomEcho, pin: $pin, contextLED: "G26")
}

#Preview("Hue knob on G33, Lite") {
    @Previewable @State var pin = ProtoPin.liteDemo[2]
    PinEditorView(board: .atomLite, pin: $pin, contextLED: "G26")
}

#Preview("LEDs on G1, S3") {
    @Previewable @State var pin = ProtoPin.s3Demo[1]
    PinEditorView(board: .atomS3Lite, pin: $pin, contextLED: "G2")
}

#Preview("Wiring diagrams") {
    ScrollView {
        VStack(spacing: 24) {
            WiringDiagramView(board: .atomEcho, pin: "G32", kind: .knob, contextLED: "G26").frame(height: 340)
            WiringSteps(board: .atomEcho, pin: "G32", kind: .knob)
            WiringDiagramView(board: .atomEcho, pin: "G26", kind: .leds).frame(height: 340)
            WiringSteps(board: .atomEcho, pin: "G26", kind: .leds)
            WiringDiagramView(board: .atomS3Lite, pin: "G38", kind: .toggle, contextLED: "G2").frame(height: 340)
            WiringSteps(board: .atomS3Lite, pin: "G38", kind: .toggle)
        }
        .padding()
    }
}
