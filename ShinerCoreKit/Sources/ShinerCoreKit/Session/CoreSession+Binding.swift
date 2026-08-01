import SwiftUI

public extension CoreSession {
    func binding<C>(_ key: PropertyKey<C>, default def: C.ValueType) -> Binding<C.ValueType> {
        Binding(
            get: { self.state[key] ?? def },
            set: { self.set(key, to: $0) }
        )
    }

    /// Int-backed firmware bools (mode, beatSync) as a Toggle binding.
    func boolBinding(_ key: PropertyKey<IntConverter>) -> Binding<Bool> {
        Binding(
            get: { (self.state[key] ?? 0) > 0 },
            set: { self.set(key, to: $0 ? 1 : 0) }
        )
    }
}
