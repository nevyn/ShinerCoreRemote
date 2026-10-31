import Foundation

/// The `layers` property: what the strip plays now, every layer at once. Wire format and
/// semantics: the firmware's docs/ble-comms.md, "The layer summary".
public struct LayerSummary: Equatable, Sendable {
    /// Whose preset the strip plays.
    public enum Source: Equatable, Sendable {
        /// The core's own preset, 0 ..< `CoreProps.presetCount`.
        case preset(Int)
        /// A neighbor's preset, while the mesh carousel plays it.
        case neighbor
    }

    /// A layer whose animation is not Nothing.
    public struct Layer: Equatable, Sendable, Identifiable {
        /// The layer's slot, 0 ..< `CoreProps.layerCount`. Wiring and layer gates name slots.
        public var index: Int
        public var look: LayerLook
        /// False while a switch or button holds the layer gate closed, which hides the layer.
        public var gateOpen: Bool

        public var id: Int { index }

        public init(index: Int, look: LayerLook, gateOpen: Bool = true) {
            self.index = index
            self.look = look
            self.gateOpen = gateOpen
        }
    }

    public var source: Source
    /// Bottom layer first, by ascending `index`.
    public var layers: [Layer]

    public init(source: Source, layers: [Layer]) {
        self.source = source
        self.layers = layers
    }

    /// Decodes the property's text, resolving animation and blend mode indices to names
    /// through `documentation`. The error names the first line that fails.
    public init(wire: String, documentation: Documentation) throws(LayerSummaryError) {
        var lines = wire.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.count > 1, lines.last == "" { lines.removeLast() }
        let header = lines[0]
        let headerFields = header.split(separator: " ")
        switch (headerFields.first, headerFields.count) {
        case ("M", 1):
            source = .neighbor
        case ("P", 2):
            guard let preset = Int(headerFields[1]), (0 ..< CoreProps.presetCount).contains(preset) else {
                throw LayerSummaryError(line: 1, text: header, reason: "the preset must be 0-\(CoreProps.presetCount - 1)")
            }
            source = .preset(preset)
        default:
            throw LayerSummaryError(line: 1, text: header, reason: "expected \"P n\" or \"M\"")
        }
        layers = []
        for (offset, text) in lines.enumerated().dropFirst() {
            let layer: Layer
            do {
                layer = try Self.layer(text, documentation: documentation)
            } catch {
                throw LayerSummaryError(line: offset + 1, text: text, reason: error.reason)
            }
            if let previous = layers.last, layer.index <= previous.index {
                throw LayerSummaryError(line: offset + 1, text: text, reason: "layer \(layer.index) comes after layer \(previous.index); layers must be bottom first")
            }
            layers.append(layer)
        }
    }

    private struct FieldError: Error { let reason: String }

    /// `index animation blend color color2 speed tau phi beatSync gate`
    private static func layer(_ text: String, documentation: Documentation) throws(FieldError) -> Layer {
        let fields = text.split(separator: " ").map(String.init)
        guard fields.count == 10 else { throw FieldError(reason: "expected 10 fields, found \(fields.count)") }
        func int(_ i: Int, _ name: String, in range: Range<Int>) throws(FieldError) -> Int {
            guard let value = Int(fields[i]), range.contains(value) else {
                throw FieldError(reason: range.isEmpty ? "\(name) \(fields[i]) is unknown: documentation lists none"
                                                       : "\(name) must be \(range.lowerBound)-\(range.upperBound - 1), not \(fields[i])")
            }
            return value
        }
        func color(_ i: Int, _ name: String) throws(FieldError) -> PixelColor {
            guard let color = PixelColor(hex: fields[i]) else { throw FieldError(reason: "\(name) must be rrggbb, not \(fields[i])") }
            return color
        }
        func number(_ i: Int, _ name: String) throws(FieldError) -> Double {
            guard let value = Double(fields[i]), value.isFinite else { throw FieldError(reason: "\(name) is not a number: \(fields[i])") }
            return value
        }
        let index = try int(0, "index", in: 0 ..< CoreProps.layerCount)
        let animation = try int(1, "animation", in: documentation.animations.indices)
        let blend = try int(2, "blend", in: documentation.blendModes.indices)
        let look = LayerLook(
            animation: documentation.animations[animation],
            blendMode: documentation.blendModes[blend],
            color1: try color(3, "color"),
            color2: try color(4, "color2"),
            speed: try number(5, "speed"),
            beatSynced: try int(8, "beatSync", in: 0 ..< 2) == 1,
            tau: try number(6, "tau"),
            phi: try number(7, "phi"))
        return Layer(index: index, look: look, gateOpen: try int(9, "gate", in: 0 ..< 2) == 1)
    }

    /// Decodes `layerOpacities`: exactly `CoreProps.layerCount` numbers 0-1 separated by
    /// single spaces, slot 0 first, e.g. `1 0.3 1 1 1 1 1 1 1 1`. The error's reason names
    /// the first slot that fails.
    public static func opacities(wire: String) throws(LayerSummaryError) -> [Double] {
        func failure(_ reason: String) -> LayerSummaryError {
            LayerSummaryError(line: 1, text: wire, reason: "layerOpacities \(reason)")
        }
        let fields = wire.split(separator: " ", omittingEmptySubsequences: false)
        guard fields.count == CoreProps.layerCount else {
            throw failure("must list \(CoreProps.layerCount) opacities, found \(fields.count)")
        }
        var opacities: [Double] = []
        for (slot, field) in fields.enumerated() {
            guard let value = Double(field), value.isFinite else { throw failure("slot \(slot) is not a number: \"\(field)\"") }
            guard (0 ... 1).contains(value) else { throw failure("slot \(slot) must be 0-1, not \(field)") }
            opacities.append(value)
        }
        return opacities
    }

    /// Sets each layer's opacity to its slot's entry in `opacities`, one per slot.
    public mutating func apply(opacities: [Double]) {
        precondition(opacities.count == CoreProps.layerCount, "expected \(CoreProps.layerCount) opacities, got \(opacities.count)")
        for i in layers.indices { layers[i].look.opacity = opacities[layers[i].index] }
    }

    /// The layer in `slot`, nil for an empty slot.
    public func layer(at slot: Int) -> Layer? {
        layers.first { $0.index == slot }
    }

    /// The first slot whose animation is Nothing; nil when all ten are used.
    public var firstEmptySlot: Int? {
        (0 ..< CoreProps.layerCount).first { layer(at: $0) == nil }
    }

    /// The stack after the firmware's layer move: the layer in `from` goes to `to` and the
    /// layers in between shift by one slot. Gates stay with their slot; a slot whose gate
    /// isn't known here (it was empty) reads as open.
    public func moving(from: Int, to: Int) -> LayerSummary {
        func destination(_ slot: Int) -> Int {
            if slot == from { return to }
            if from < to, (from + 1 ... to).contains(slot) { return slot - 1 }
            if to < from, (to ..< from).contains(slot) { return slot + 1 }
            return slot
        }
        let gates = Dictionary(uniqueKeysWithValues: layers.map { ($0.index, $0.gateOpen) })
        let moved = layers.map { layer in
            let slot = destination(layer.index)
            return Layer(index: slot, look: layer.look, gateOpen: gates[slot] ?? true)
        }
        return LayerSummary(source: source, layers: moved.sorted { $0.index < $1.index })
    }

    /// The `layerMove` that puts a layer where a list shows it after a drag, for a list
    /// that shows `layers` front-most first. `source` and `destination` are the list's own
    /// move offsets (SwiftUI `onMove`: `destination` counts rows before the move). Nil
    /// when the drop leaves the order as it was.
    public func layerMove(fromRow source: Int, toRow destination: Int) -> (from: Int, to: Int)? {
        let rows = layers.reversed().map(\.index)
        guard rows.indices.contains(source), (0 ... rows.count).contains(destination),
              destination != source, destination != source + 1 else { return nil }
        // Moving toward the back, the layer lands just behind the row above the drop;
        // toward the front, just in front of the row below it.
        let to = destination > source ? rows[destination - 1] : rows[destination]
        return (rows[source], to)
    }
}

/// Why a `layers` value was rejected: the 1-based line, its text, and what was wrong.
public struct LayerSummaryError: Error, Equatable, Sendable, CustomStringConvertible {
    public let line: Int
    public let text: String
    public let reason: String

    public var description: String { "line \(line) \"\(text)\": \(reason)" }
}

public extension PixelColor {
    /// Parses six hex digits `rrggbb`, as the layer summary sends colors.
    init?(hex: String) {
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit), let value = UInt32(hex, radix: 16) else { return nil }
        self.init(r: UInt8(value >> 16), g: UInt8((value >> 8) & 0xff), b: UInt8(value & 0xff))
    }

    /// Six lowercase hex digits `rrggbb`.
    var hex: String { String(format: "%02x%02x%02x", r, g, b) }
}

public extension Wiring {
    /// Pins whose role names layer `slot` (layer-on switches, layer toggle buttons, layer
    /// knobs), in board order with the front button last.
    func pins(controllingLayer slot: Int, docs: WiringDocs) -> [String] {
        (docs.pins + [docs.frontButton].compactMap { $0 }).filter { pin in
            switch role(of: pin, docs: docs) {
            case .switch(.layerOn(slot)), .button(.toggleLayer(slot)): true
            case .knob(let knob): knob.layer == slot
            default: false
            }
        }
    }
}

public extension LayerSummary {
    /// After a layer move, which wired controls now act on another layer, e.g. "The switch
    /// on G23 now controls Comet." Nil when no wired slot changed hands. Wiring names
    /// slots, so a move can hand a switch somebody else's layer.
    static func wiringNotice(before: LayerSummary, after: LayerSummary, wiring: Wiring, docs: WiringDocs) -> String? {
        let sentences = (0 ..< CoreProps.layerCount).flatMap { slot -> [String] in
            let now = after.layer(at: slot)
            guard before.layer(at: slot)?.look != now?.look else { return [] }
            return wiring.pins(controllingLayer: slot, docs: docs).map { pin in
                let control = switch wiring.role(of: pin, docs: docs) {
                case _ where pin == docs.frontButton: "The front button"
                case .switch: "The switch on \(pin)"
                case .knob: "The knob on \(pin)"
                default: "The button on \(pin)"
                }
                return "\(control) now controls \(now.map(\.look.animation) ?? "an empty layer")."
            }
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }
}
