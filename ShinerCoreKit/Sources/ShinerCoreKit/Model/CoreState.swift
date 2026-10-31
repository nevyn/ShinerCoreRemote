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
    /// The `layers` property decoded: what the strip plays now. Nil until both it and
    /// `documentation` arrive, or while `layerSummaryError` says why it can't be read.
    public var layerSummary: LayerSummary?
    public var layerSummaryError: LayerSummaryError?
    /// The last summary of the core's own preset. The mesh carousel takes turns, so this
    /// outlives a neighbor's turn; `ownLayers` checks that it is still current.
    public var ownLayerSummary: LayerSummary?

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

public extension CoreState {
    /// The core's own layers of the current preset, nil while unknown.
    var ownLayers: LayerSummary? {
        guard let own = ownLayerSummary, let preset = self[CoreProps.preset], own.source == .preset(preset) else { return nil }
        return own
    }

    /// The core's own layers of the current preset, bottom first, with the cursor's layer
    /// taken from the per-layer properties, which follow edits at once while the summary
    /// waits for the next revision. Nil while unknown.
    var stack: [LayerSummary.Layer]? {
        ownLayers.map(withCursorLayer)
    }

    /// What the strip plays now, bottom first: `stack`, or the summary as it is while it
    /// describes something else (a neighbor's preset). Nil while unknown.
    var playingLayers: [LayerSummary.Layer]? {
        guard let summary = layerSummary else { return nil }
        return summary == ownLayers ? withCursorLayer(summary) : summary.layers
    }

    private func withCursorLayer(_ summary: LayerSummary) -> [LayerSummary.Layer] {
        guard let slot = self[CoreProps.layer], CoreProps.perLayer.allSatisfy({ raw[$0] != nil }),
              let look = layerLook else { return summary.layers }
        var layers = summary.layers.filter { $0.index != slot }
        if look.animation != documentation?.animations.first {
            layers.append(LayerSummary.Layer(index: slot, look: look, gateOpen: summary.layer(at: slot)?.gateOpen ?? true))
            layers.sort { $0.index < $1.index }
        }
        return layers
    }
}
