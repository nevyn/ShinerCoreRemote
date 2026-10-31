import Foundation

/// A snapshot of everything known about a core. Pure data: buildable in
/// tests and previews without a device.
public struct CoreState: Equatable, Sendable {
    /// Wire values as last read or optimistically written.
    public var raw: [PropertyID: String] = [:]
    /// Properties the connected firmware actually exposes.
    public var available: Set<PropertyID> = []
    /// Decoded once when the documentation property arrives.
    public var documentation: Documentation?
    /// Decoded once when the animationDocs property arrives; nil when it doesn't
    /// match `documentation`, so that animations never get another's docs.
    public var animationDocs: AnimationDocs?
    /// Decoded once when the wiringDocs property arrives.
    public var wiringDocs: WiringDocs?

    public init() {}

    public subscript<C>(key: PropertyKey<C>) -> C.ValueType? {
        raw[key.id].flatMap(C.convert)
    }

    public func isAvailable<C>(_ key: PropertyKey<C>) -> Bool {
        available.contains(key.id)
    }

    public func rawValue<C>(of key: PropertyKey<C>) -> String? {
        raw[key.id]
    }
}

public extension CoreState {
    /// The closed switch that holds the lights on or off right now, if any.
    var lightsHold: (pin: String, on: Bool)? {
        guard let docs = wiringDocs, let wiring = self[CoreProps.wiring], let status = self[CoreProps.pinStatus] else { return nil }
        return wiring.lightsHold(docs: docs, status: status)
    }

    /// The closed switch that holds a preset right now, if any.
    var presetHold: (pin: String, preset: Int)? {
        guard let docs = wiringDocs, let wiring = self[CoreProps.wiring], let status = self[CoreProps.pinStatus] else { return nil }
        return wiring.presetHold(docs: docs, status: status)
    }
}
