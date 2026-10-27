import Foundation

/// The `wiringDocs` property: the board's pins and what each can do. Static
/// per firmware build, read once per connection.
public struct WiringDocs: Equatable, Sendable {
    /// `atom-lite`, `atom-echo` or `atoms3-lite`; the app keys board drawings on it.
    public let board: String
    /// Every wiring pin, in status bit order.
    public let pins: [String]
    /// Pins that can be knobs.
    public let analog: Set<String>
    /// Pins that can be LEDs.
    public let led: Set<String>
    /// Pins that built-in hardware can claim, and by what ("speaker", "microphone").
    /// `PinStatus` says whether a claim is active.
    public let claims: [String: String]
    /// Knob targets that this firmware supports and the app knows, in firmware order.
    public let targets: [KnobTarget]

    public init(board: String, pins: [String], analog: Set<String>, led: Set<String>,
                claims: [String: String], targets: [KnobTarget]) {
        self.board = board
        self.pins = pins
        self.analog = analog
        self.led = led
        self.claims = claims
        self.targets = targets
    }

    /// Analog pins in status bit order: the order of `PinStatus.positions`.
    public var analogPins: [String] { pins.filter(analog.contains) }

    /// Decodes and checks the value. Targets this app doesn't know are skipped:
    /// newer firmware may offer more.
    public init(json: String) throws(WiringError) {
        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: Data(json.utf8))
        } catch {
            throw .malformed("wiringDocs: \(error)")
        }
        guard wire.pins.count <= 8 else { throw .malformed("wiringDocs lists \(wire.pins.count) pins; pinStatus masks hold 8") }
        if let bad = wire.pins.first(where: { !isPinLabel($0) }) { throw .unknownPin(bad) }
        let pins = Set(wire.pins)
        if let bad = (wire.analog + wire.led + wire.claims.keys).first(where: { !pins.contains($0) }) {
            throw .unknownPin(bad)
        }
        self.init(board: wire.board, pins: wire.pins, analog: Set(wire.analog), led: Set(wire.led),
                  claims: wire.claims, targets: wire.targets.compactMap(KnobTarget.init(id:)))
    }

    private struct Wire: Decodable {
        let board: String
        let pins: [String]
        let analog: [String]
        let led: [String]
        let claims: [String: String]
        let targets: [String]
    }
}

public struct WiringDocsConverter: PropertyConverter {
    /// Nil for a value that fails to decode; `CoreSession` reports why.
    public static func convert(_ raw: String) -> WiringDocs? { try? WiringDocs(json: raw) }
    public static func unconvert(_ value: WiringDocs) -> String {
        preconditionFailure("wiringDocs is read-only")
    }
}
