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
