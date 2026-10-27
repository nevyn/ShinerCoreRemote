import Foundation

/// The `pinStatus` property: live pin state, notified on change. Wire format
/// is lowercase hex `rr cc mm pp...`; see the firmware's docs/wiring.md.
public struct PinStatus: Equatable, Sendable {
    /// Wiring revision mod 256; it changes on every `wiring` write, so a
    /// client re-reads `wiring` when it does.
    public let revision: UInt8
    /// Bit i set: pin i (status bit order) is connected to G.
    public let closed: UInt8
    /// Bit i set: pin i is claimed by built-in hardware right now.
    public let claimed: UInt8
    /// Filtered position 0-255 of each analog pin, in status bit order.
    public let positions: [UInt8]

    public init(revision: UInt8, closed: UInt8, claimed: UInt8, positions: [UInt8]) {
        self.revision = revision
        self.closed = closed
        self.claimed = claimed
        self.positions = positions
    }

    public init(hex: String) throws(WiringError) {
        let digits = Array(hex.utf8)
        guard digits.count >= 6, digits.count <= 40, digits.count.isMultiple(of: 2) else {
            throw .malformed("pinStatus \"\(hex)\" has \(digits.count) hex digits")
        }
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: digits.count, by: 2) {
            guard let high = nibble(digits[i]), let low = nibble(digits[i + 1]) else {
                throw .malformed("pinStatus \"\(hex)\" is not hex")
            }
            bytes.append(high << 4 | low)
        }
        self.init(revision: bytes[0], closed: bytes[1], claimed: bytes[2], positions: Array(bytes[3...]))
    }

    public var hex: String {
        ([revision, closed, claimed] + positions).map { String(format: "%02x", $0) }.joined()
    }

    /// The state of `pin`, or nil if `docs` has no such pin.
    public func state(of pin: String, in docs: WiringDocs) -> PinState? {
        guard let bit = docs.pins.firstIndex(of: pin), bit < 8 else { return nil }
        let position = docs.analogPins.firstIndex(of: pin).flatMap { positions.indices.contains($0) ? positions[$0] : nil }
        return PinState(closed: closed >> bit & 1 == 1, claimed: claimed >> bit & 1 == 1, position: position)
    }
}

public struct PinState: Equatable, Sendable {
    public let closed: Bool
    public let claimed: Bool
    /// 0-255 for analog pins; nil for the rest.
    public let position: UInt8?

    public init(closed: Bool, claimed: Bool, position: UInt8?) {
        self.closed = closed
        self.claimed = claimed
        self.position = position
    }
}

public struct PinStatusConverter: PropertyConverter {
    /// Nil for a value that fails to decode; `CoreSession` reports why.
    public static func convert(_ raw: String) -> PinStatus? { try? PinStatus(hex: raw) }
    public static func unconvert(_ value: PinStatus) -> String { value.hex }
}

private func nibble(_ c: UInt8) -> UInt8? {
    switch c {
    case UInt8(ascii: "0") ... UInt8(ascii: "9"): c - UInt8(ascii: "0")
    case UInt8(ascii: "a") ... UInt8(ascii: "f"): c - UInt8(ascii: "a") + 10
    default: nil
    }
}
