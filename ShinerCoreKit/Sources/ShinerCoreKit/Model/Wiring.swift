import Foundation

/// A core's map from pin label to role. A pin that is absent has role nothing.
/// Wire format and validation: the firmware's docs/wiring.md.
public struct Wiring: Equatable, Sendable {
    public var roles: [String: PinRole]

    public init(_ roles: [String: PinRole] = [:]) { self.roles = roles }

    public subscript(pin: String) -> PinRole? {
        get { roles[pin] }
        set { roles[pin] = newValue }
    }

    /// Decodes the `wiring` value, rejecting what the firmware would reject
    /// where that is knowable without the board's pin table.
    public init(json: String) throws(WiringError) {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        } catch {
            throw .malformed(error.localizedDescription)
        }
        guard let object = parsed as? [String: Any] else { throw .malformed("not a JSON object") }
        var roles: [String: PinRole] = [:]
        for (pin, value) in object {
            guard isPinLabel(pin) else { throw .unknownPin(pin) }
            guard let fields = value as? [String: Any] else { throw .malformed("\(pin) is not an object") }
            roles[pin] = try PinRole(pin: pin, fields: fields)
        }
        self.roles = roles
    }

    /// Pins in label order, keys in the contract's order, numbers in shortest form.
    public var json: String {
        let pins = roles.keys.sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        return "{" + pins.map { "\"\($0)\":\(roles[$0]!.json)" }.joined(separator: ",") + "}"
    }
}

// MARK: - Held settings

public extension Wiring {
    /// The closed switch that holds the lights on or off right now, if any.
    /// A closed `lightsOff` beats a closed `lightsOn`; claimed pins hold nothing.
    func lightsHold(docs: WiringDocs, status: PinStatus) -> (pin: String, on: Bool)? {
        let closed = closedSwitches(docs: docs, status: status)
        if let off = closed.first(where: { $0.action == .lightsOff }) { return (off.pin, false) }
        if let on = closed.first(where: { $0.action == .lightsOn }) { return (on.pin, true) }
        return nil
    }

    /// The closed switch that holds a preset right now, if any: the first in status bit order.
    func presetHold(docs: WiringDocs, status: PinStatus) -> (pin: String, preset: Int)? {
        for (pin, action) in closedSwitches(docs: docs, status: status) {
            if case .preset(let preset) = action { return (pin, preset) }
        }
        return nil
    }

    private func closedSwitches(docs: WiringDocs, status: PinStatus) -> [(pin: String, action: SwitchAction)] {
        docs.pins.compactMap { pin in
            guard case .switch(let action) = roles[pin],
                  let state = status.state(of: pin, in: docs), state.closed, !state.claimed
            else { return nil }
            return (pin, action)
        }
    }
}

public enum PinRole: Equatable, Sendable {
    case leds
    case `switch`(SwitchAction)
    case button(ButtonAction)
    case knob(Knob)
}

/// What a closed switch holds.
public enum SwitchAction: Equatable, Sendable {
    case lightsOff
    case lightsOn
    /// 0-4
    case preset(Int)
    /// 0-9
    case layerOn(Int)
}

/// What a button press does.
public enum ButtonAction: Equatable, Sendable {
    /// Cycles presets on release; toggles lights after a 600 ms hold.
    case nextPreset
    case toggleLights
    /// 0-4
    case preset(Int)
    /// 0-9
    case toggleLayer(Int)
}

/// A knob writes `target` with values from `min` (fully left) to `max`
/// (fully right), in target units. `min > max` reverses the knob.
public struct Knob: Equatable, Sendable {
    public var target: KnobTarget
    /// The layer of the current preset that the knob writes; non-nil exactly
    /// when `target.isLayerTarget`.
    public var layer: Int?
    public var min: Double
    public var max: Double

    public init(target: KnobTarget, layer: Int? = nil, min: Double, max: Double) {
        self.target = target
        self.layer = layer
        self.min = min
        self.max = max
    }
}

/// The setting that a knob writes.
public enum KnobTarget: Hashable, Sendable, CaseIterable {
    case brightness
    case speed
    case tau
    case phi
    case color(ColorSlot, ColorChannel)

    public enum ColorSlot: String, Sendable, CaseIterable {
        case primary = "color1", secondary = "color2"
    }

    /// r, g, b, and FastLED's 0-255 hue, saturation and value.
    public enum ColorChannel: String, Sendable, CaseIterable {
        case red = "r", green = "g", blue = "b", hue = "h", saturation = "s", value = "v"
    }

    public static let allCases: [KnobTarget] = [.brightness, .speed, .tau, .phi]
        + ColorSlot.allCases.flatMap { slot in ColorChannel.allCases.map { .color(slot, $0) } }

    /// The wire id, such as `brightness` or `color1.h`.
    public var id: String {
        switch self {
        case .brightness: "brightness"
        case .speed: "speed"
        case .tau: "tau"
        case .phi: "phi"
        case .color(let slot, let channel): "\(slot.rawValue).\(channel.rawValue)"
        }
    }

    public init?(id: String) {
        guard let target = Self.allCases.first(where: { $0.id == id }) else { return nil }
        self = target
    }

    /// Layer targets address one layer of the current preset; brightness is global.
    public var isLayerTarget: Bool { self != .brightness }

    /// The values that the firmware accepts for `min` and `max`.
    public var validRange: ClosedRange<Double> {
        switch self {
        case .brightness, .color: 0 ... 255
        case .speed: 0.001 ... 100
        case .tau, .phi: -100 ... 100
        }
    }
}

/// Why a `wiring`, `wiringDocs` or `pinStatus` value was rejected; each case
/// names the offending pin and key.
public enum WiringError: Error, Equatable, Sendable, CustomStringConvertible {
    case malformed(String)
    case unknownPin(String)
    case unknownRole(pin: String)
    case unknownAction(pin: String, String)
    case unknownTarget(pin: String, String)
    case missingKey(pin: String, String)
    case unexpectedKey(pin: String, String)
    case outOfRange(pin: String, String)

    public var description: String {
        switch self {
        case .malformed(let detail): "wiring is malformed: \(detail)"
        case .unknownPin(let pin): "\"\(pin)\" is not a pin label"
        case .unknownRole(let pin): "\(pin) has no known role"
        case .unknownAction(let pin, let action): "\(pin) has unknown action \"\(action)\""
        case .unknownTarget(let pin, let target): "\(pin) has unknown knob target \"\(target)\""
        case .missingKey(let pin, let key): "\(pin) is missing \"\(key)\""
        case .unexpectedKey(let pin, let key): "\(pin) has unexpected key \"\(key)\""
        case .outOfRange(let pin, let key): "\(pin) has \"\(key)\" out of range"
        }
    }
}

public struct WiringConverter: PropertyConverter {
    /// Nil for a value that fails to decode; `CoreSession` reports why.
    public static func convert(_ raw: String) -> Wiring? { try? Wiring(json: raw) }
    public static func unconvert(_ value: Wiring) -> String { value.json }
}

/// Case-printed pin labels are short and alphanumeric ("G32").
func isPinLabel(_ label: String) -> Bool {
    !label.isEmpty && label.count <= 8 && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
}

// MARK: - Coding

private let roleKeys = ["leds", "switch", "button", "knob"]

private extension PinRole {
    init(pin: String, fields: [String: Any]) throws(WiringError) {
        let present = roleKeys.filter { fields[$0] != nil }
        guard present.count == 1, let roleKey = present.first else { throw .unknownRole(pin: pin) }
        var reader = FieldReader(pin: pin, fields: fields)
        switch roleKey {
        case "leds":
            guard try reader.bool("leds") else { throw .unknownRole(pin: pin) }
            self = .leds
        case "switch":
            let action = try reader.string("switch")
            switch action {
            case "lightsOff": self = .switch(.lightsOff)
            case "lightsOn": self = .switch(.lightsOn)
            case "preset": self = .switch(.preset(try reader.int("preset", in: 0 ... 4)))
            case "layerOn": self = .switch(.layerOn(try reader.int("layer", in: 0 ... 9)))
            default: throw .unknownAction(pin: pin, action)
            }
        case "button":
            let action = try reader.string("button")
            switch action {
            case "nextPreset": self = .button(.nextPreset)
            case "toggleLights": self = .button(.toggleLights)
            case "preset": self = .button(.preset(try reader.int("preset", in: 0 ... 4)))
            case "toggleLayer": self = .button(.toggleLayer(try reader.int("layer", in: 0 ... 9)))
            default: throw .unknownAction(pin: pin, action)
            }
        default:
            let id = try reader.string("knob")
            guard let target = KnobTarget(id: id) else { throw .unknownTarget(pin: pin, id) }
            let layer = target.isLayerTarget ? try reader.int("layer", in: 0 ... 9) : nil
            let min = try reader.double("min", in: target.validRange)
            let max = try reader.double("max", in: target.validRange)
            self = .knob(Knob(target: target, layer: layer, min: min, max: max))
        }
        try reader.rejectUnread()
    }

    var json: String {
        switch self {
        case .leds: return #"{"leds":true}"#
        case .switch(let action):
            switch action {
            case .lightsOff: return #"{"switch":"lightsOff"}"#
            case .lightsOn: return #"{"switch":"lightsOn"}"#
            case .preset(let n): return #"{"switch":"preset","preset":\#(n)}"#
            case .layerOn(let n): return #"{"switch":"layerOn","layer":\#(n)}"#
            }
        case .button(let action):
            switch action {
            case .nextPreset: return #"{"button":"nextPreset"}"#
            case .toggleLights: return #"{"button":"toggleLights"}"#
            case .preset(let n): return #"{"button":"preset","preset":\#(n)}"#
            case .toggleLayer(let n): return #"{"button":"toggleLayer","layer":\#(n)}"#
            }
        case .knob(let knob):
            precondition((knob.layer != nil) == knob.target.isLayerTarget, "knob layer must match its target")
            let layer = knob.layer.map { #","layer":\#($0)"# } ?? ""
            return #"{"knob":"\#(knob.target.id)"\#(layer),"min":\#(shortest(knob.min)),"max":\#(shortest(knob.max))}"#
        }
    }
}

private func shortest(_ value: Double) -> String {
    value == value.rounded() && abs(value) < 1e9 ? String(Int(value)) : String(value)
}

/// Reads typed fields from one pin's object and remembers which keys it consumed.
private struct FieldReader {
    let pin: String
    let fields: [String: Any]
    var read: Set<String> = []

    init(pin: String, fields: [String: Any]) {
        self.pin = pin
        self.fields = fields
    }

    mutating func value(_ key: String) throws(WiringError) -> Any {
        guard let value = fields[key] else { throw .missingKey(pin: pin, key) }
        read.insert(key)
        return value
    }

    mutating func bool(_ key: String) throws(WiringError) -> Bool {
        guard let number = try value(key) as? NSNumber, number.isBool else { throw .malformed("\(pin).\(key) is not a boolean") }
        return number.boolValue
    }

    mutating func string(_ key: String) throws(WiringError) -> String {
        guard let string = try value(key) as? String else { throw .malformed("\(pin).\(key) is not a string") }
        return string
    }

    mutating func double(_ key: String, in range: ClosedRange<Double>) throws(WiringError) -> Double {
        guard let number = try value(key) as? NSNumber, !number.isBool else { throw .malformed("\(pin).\(key) is not a number") }
        guard range.contains(number.doubleValue) else { throw .outOfRange(pin: pin, key) }
        return number.doubleValue
    }

    mutating func int(_ key: String, in range: ClosedRange<Int>) throws(WiringError) -> Int {
        let value = try double(key, in: Double(range.lowerBound) ... Double(range.upperBound))
        guard value == value.rounded() else { throw .malformed("\(pin).\(key) is not an integer") }
        return Int(value)
    }

    func rejectUnread() throws(WiringError) {
        if let extra = Set(fields.keys).subtracting(read).sorted().first {
            throw .unexpectedKey(pin: pin, extra)
        }
    }
}

private extension NSNumber {
    var isBool: Bool { CFGetTypeID(self) == CFBooleanGetTypeID() }
}
