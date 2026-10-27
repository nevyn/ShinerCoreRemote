import SwiftUI
import ShinerCoreKit

/// The Wiring tab: one row per pin of the board, with its role and live state.
struct WiringView: View {
    let session: CoreSession
    @State private var editing: EditTarget?

    private struct EditTarget: Identifiable { let id: String }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let docs = session.state.wiringDocs {
                    content(docs)
                } else if session.connection == .connected, !session.state.isAvailable(CoreProps.wiringDocs) {
                    Text("This core's firmware predates wiring; update it to add switches, buttons and knobs.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding()
        }
        .sheet(item: $editing) { target in
            if let docs = session.state.wiringDocs {
                PinEditorView(session: session, pin: target.id, docs: docs)
            }
        }
    }

    @ViewBuilder private func content(_ docs: WiringDocs) -> some View {
        let layout = BoardLayout(board: docs.board)
        let status = session.state[CoreProps.pinStatus]
        if let raw = session.state.rawValue(of: CoreProps.wiring) {
            if let wiring = WiringConverter.convert(raw) {
                let pins = WiringPin.all(docs: docs, wiring: wiring, status: status, layout: layout)
                if let layout {
                    BoardFaceView(board: layout, emphasis: emphasis(pins))
                        .frame(height: 200)
                        .accessibilityHidden(true)
                }
                VStack(spacing: 0) {
                    ForEach(pins) { pin in
                        if pin.claim == nil {
                            Button { editing = EditTarget(id: pin.id) } label: { PinRow(pin: pin) }
                                .buttonStyle(.plain)
                        } else {
                            PinRow(pin: pin)
                        }
                        if pin.id != pins.last?.id { Divider().padding(.leading, 64) }
                    }
                }
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                Text("Wiggle a switch or turn a knob to see which row reacts. Wiring is the same in every preset.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Label("This core's wiring uses something this app doesn't know. Update the app to edit it.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private func emphasis(_ pins: [WiringPin]) -> [String: Color] {
        var e: [String: Color] = [:]
        for pin in pins where pin.claim == nil && pin.role != nil { e[pin.id] = RoleKind(pin.role).tint }
        return e
    }
}

/// One row's worth of state: what the docs, the wiring and pinStatus say about a pin.
struct WiringPin: Identifiable, Equatable {
    let id: String
    let role: PinRole?
    let analog: Bool
    /// What holds the pin right now ("the speaker"); nil when the pin is free.
    let claim: String?
    let state: PinState?

    /// Grove signal pins first, then the header, with pins that hardware can claim last.
    static func all(docs: WiringDocs, wiring: Wiring, status: PinStatus?, layout: BoardLayout?) -> [WiringPin] {
        let order = docs.pins.enumerated().sorted { a, b in
            func rank(_ p: (offset: Int, element: String)) -> (Int, Int, Int) {
                (docs.claims[p.element] == nil ? 0 : 1, layout?.isGroveSignal(p.element) == true ? 0 : 1, p.offset)
            }
            return rank(a) < rank(b)
        }
        return order.map { _, pin in
            let state = status?.state(of: pin, in: docs)
            // Until pinStatus arrives, assume a claimable pin is claimed: writes to it may be rejected.
            let claimed = state?.claimed ?? (docs.claims[pin] != nil)
            return WiringPin(id: pin, role: wiring[pin], analog: docs.analog.contains(pin),
                             claim: claimed ? docs.claims[pin].map { "the \($0)" } : nil, state: state)
        }
    }
}

enum RoleKind: String, CaseIterable, Identifiable {
    case nothing = "Nothing", `switch` = "Switch", button = "Button", knob = "Knob", leds = "LEDs"
    var id: Self { self }

    init(_ role: PinRole?) {
        switch role {
        case nil: self = .nothing
        case .leds: self = .leds
        case .switch: self = .switch
        case .button: self = .button
        case .knob: self = .knob
        }
    }

    var symbol: String {
        switch self {
        case .nothing: "circle.dashed"
        case .switch: "switch.2"
        case .button: "button.programmable"
        case .knob: "dial.medium"
        case .leds: "lightbulb.led"
        }
    }

    var tint: Color {
        switch self {
        case .nothing: .gray
        case .switch: .blue
        case .button: .purple
        case .knob: .orange
        case .leds: .pink
        }
    }
}

extension Optional where Wrapped == PinRole {
    /// One line on what the role does, for the pin's row.
    var summary: String {
        switch self {
        case nil: "Not used"
        case .leds: "LED strip data"
        case .switch(let action):
            switch action {
            case .lightsOff: "Closed: lights off"
            case .lightsOn: "Closed: lights on"
            case .preset(let n): "Closed: preset \(n)"
            case .layerOn(let n): "Closed: layer \(n) on"
            }
        case .button(let action):
            switch action {
            case .nextPreset: "Next preset · hold: lights on/off"
            case .toggleLights: "Lights on/off"
            case .preset(let n): "Preset \(n)"
            case .toggleLayer(let n): "Layer \(n) on/off"
            }
        case .knob(let knob):
            if let layer = knob.layer { "Layer \(layer) · \(knob.target.name)" } else { knob.target.name }
        }
    }
}

struct PinRow: View {
    let pin: WiringPin

    var body: some View {
        let kind = RoleKind(pin.role)
        HStack(spacing: 12) {
            Text(pin.id)
                .font(.system(.subheadline, design: .monospaced).bold())
                .foregroundStyle(pin.claim == nil ? .white : .secondary)
                .frame(width: 44, height: 28)
                .background(pin.claim == nil ? kind.tint : Color.gray.opacity(0.25),
                            in: RoundedRectangle(cornerRadius: 6))
            if let claim = pin.claim {
                Text("Used by \(claim)").foregroundStyle(.secondary)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Label(kind.rawValue, systemImage: kind.symbol)
                        .font(.headline)
                    Text(pin.role.summary)
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
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct LiveIndicator: View {
    let pin: WiringPin

    var body: some View {
        switch RoleKind(pin.role) {
        case .leds:
            EmptyView()
        case .knob:
            positionBar
        case .nothing where pin.analog:
            positionBar
        default:
            let closed = pin.state?.closed ?? false
            VStack(spacing: 2) {
                Circle()
                    .fill(closed ? Color.green : Color.clear)
                    .stroke(closed ? Color.green : Color.gray, lineWidth: 2)
                    .frame(width: 14, height: 14)
                Text(closed ? "closed" : "open")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var positionBar: some View {
        let fraction = Double(pin.state?.position ?? 0) / 255
        return Capsule()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 56, height: 8)
            .overlay(alignment: .leading) {
                Capsule().fill(Color.orange).frame(width: 56 * fraction, height: 8)
            }
            .accessibilityLabel("at \(Int((fraction * 100).rounded()))%")
    }
}

// MARK: - Previews

#Preview("Wiring, Atom Echo") {
    let session = CoreSession(link: FakeCoreLink.demo(board: .atomEcho))
    NavigationStack {
        CoreControlsView(session: session, tab: .wiring).navigationTitle("Gustav")
    }
    .task { await session.run() }
}

#Preview("Wiring, Atom Lite") {
    let session = CoreSession(link: FakeCoreLink.demo(board: .atomLite))
    NavigationStack {
        CoreControlsView(session: session, tab: .wiring).navigationTitle("Vindarnas hus")
    }
    .task { await session.run() }
}

#Preview("Wiring, AtomS3 Lite") {
    let session = CoreSession(link: FakeCoreLink.demo(board: .atomS3Lite))
    NavigationStack {
        CoreControlsView(session: session, tab: .wiring).navigationTitle("Nevyn")
    }
    .task { await session.run() }
}

#Preview("Wiring, old firmware") {
    let link = FakeCoreLink.demo()
    for key in [CoreProps.wiring.id, CoreProps.pinStatus.id, CoreProps.wiringDocs.id] { link.values[key] = nil }
    let session = CoreSession(link: link)
    return NavigationStack {
        CoreControlsView(session: session, tab: .wiring).navigationTitle("Nevyn")
    }
    .task { await session.run() }
}
