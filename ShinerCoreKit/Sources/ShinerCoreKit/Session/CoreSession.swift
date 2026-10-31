import Foundation
import Observation

/// Enlivens a `CoreState` over a `CoreLink`: owns the connection lifecycle,
/// optimistic writes with throttling, and reconnection. Views observe this
/// and never see a peripheral.
@Observable @MainActor
public final class CoreSession {
    public enum ConnectionState: Equatable, Sendable {
        case connecting
        case connected
        case reconnecting
        /// Permanent: reconnecting is pointless (wrong device, forgotten peripheral).
        case failed(String)
    }

    public private(set) var state = CoreState()
    public private(set) var connection: ConnectionState = .connecting
    /// Settable so the UI can dismiss it.
    public var lastError: String?
    /// After a layer move that hands a wired control another layer, says so: "The switch
    /// on G23 now controls Comet." Nil when the last move changed no wired slot.
    public private(set) var layerMoveNotice: String?

    /// One write on its way to the core. `raw` is fixed when queued, so that a later
    /// cursor move can't redirect it. `holds` are other properties whose device values
    /// the write changes, so that their stale reads are dropped too.
    private struct Write {
        let id: PropertyID
        let name: String
        let raw: String
        var holds: [PropertyID] = []
        var then: (@MainActor () -> Void)?

        func covers(_ prop: PropertyID) -> Bool { id == prop || holds.contains(prop) }
    }

    @ObservationIgnored private let link: any CoreLink
    @ObservationIgnored private let throttle: Duration
    /// Writes reach the link one at a time, in the order queued: the core applies a
    /// per-layer write to whichever layer its cursor points at when the write arrives.
    @ObservationIgnored private var queue: [Write] = []
    @ObservationIgnored private var inFlight: Write?
    @ObservationIgnored private var writer: Task<Void, Never>?
    /// Props set during their throttle interval; each is queued, with its latest value,
    /// when the interval ends or a cursor move flushes it.
    @ObservationIgnored private var throttled: [PropertyID: (name: String, timer: Task<Void, Never>)] = [:]
    /// Outstanding read requests per prop, oldest first: exactly one valueRead/readFailed
    /// event comes back per request, in order. True marks a read requested before a
    /// write of that prop went out, whose response is stale by definition.
    @ObservationIgnored private var outstandingReads: [PropertyID: [Bool]] = [:]
    @ObservationIgnored private var hasRun = false
    /// The pinStatus revision of the wiring last read; nil until the first
    /// pinStatus after connecting, whose wiring the connect refresh reads.
    @ObservationIgnored private var wiringRevision: UInt8?
    /// The wiring last written, until the device's wiring is next read back.
    @ObservationIgnored private var expectedWiring: Wiring?
    /// The layersRevision of the layers last read; nil until the first after connecting.
    @ObservationIgnored private var layersRevision: Int?

    public init(link: any CoreLink, throttle: Duration = .milliseconds(100)) {
        self.link = link
        self.throttle = throttle
    }

    /// Runs the connection for the lifetime of the calling task.
    /// Cancellation disconnects; back = disconnect. While the task lives,
    /// a lost link reconnects automatically: `connect()` is a standing
    /// intent that completes whenever the device reappears.
    public func run() async {
        precondition(!hasRun, "CoreSession.run() is one-shot; make a new session")
        hasRun = true
        defer { link.disconnect() }
        link.connect()
        for await event in link.events {
            handle(event)
        }
    }

    private func handle(_ event: CoreLinkEvent) {
        switch event {
        case .connected:
            connection = .connected
            lastError = nil
            refresh()
        case .disconnected(let reason):
            if case .failed = connection { return }  // never reconnect an incompatible device
            connection = .reconnecting
            if let reason { lastError = reason.description }
            for (_, timer) in throttled.values { timer.cancel() }
            throttled = [:]
            queue = []  // the reconnect re-reads everything instead
            outstandingReads = [:]
            wiringRevision = nil
            layersRevision = nil
            state.available = []  // firmware may differ after reconnect; rediscovery repopulates
            link.connect()
        case .incompatible(let reason):
            connection = .failed(reason.description)
        case .becameAvailable(let id):
            state.available.insert(id)
        case .valueRead(let id, let raw):
            // Stale, or older than the optimistic value that a pending write carries.
            guard !finishRead(of: id), !isWriting(id) else { return }
            if id == CoreProps.wiring.id { confirmWiringWrite(raw) }
            applyDeviceValue(id, raw)
        case .valueChanged(let id, let raw):
            // A notification: another central, cursor fanout, or our own
            // write echoing back. No read bookkeeping — nothing was requested.
            guard !isWriting(id) else { return }
            applyDeviceValue(id, raw)
        case .readFailed(let id, let error):
            finishRead(of: id)
            lastError = "Couldn't read \(id): \(error.description)"
        }
    }

    private func applyDeviceValue(_ id: PropertyID, _ raw: String) {
        // An equal layers value still decodes: it undoes an optimistic edit that the core ignored.
        guard state.raw[id] != raw || id == CoreProps.layers.id else { return }
        state.raw[id] = raw
        switch id {
        case CoreProps.documentation.id:
            do {
                state.documentation = try Documentation(json: raw)
            } catch {
                state.documentation = nil
                let reason = (error as? DecodingError)?.summary ?? String(describing: error)
                lastError = "Core sent unreadable documentation (\(reason)); menus may be incomplete."
            }
            checkAnimationDocs()
            decodeLayers()
        case CoreProps.animationDocs.id:
            do {
                state.animationDocs = try AnimationDocs(json: raw)
            } catch {
                state.animationDocs = nil
                let reason = (error as? DecodingError)?.summary ?? String(describing: error)
                lastError = "Core sent unreadable animationDocs (\(reason)); using the app's own animation table."
            }
            checkAnimationDocs()
        case CoreProps.wiringDocs.id:
            do {
                state.wiringDocs = try WiringDocs(json: raw)
            } catch {
                state.wiringDocs = nil
                lastError = "Core sent unreadable wiring docs: \(error)"
            }
        case CoreProps.wiring.id:
            do {
                _ = try Wiring(json: raw)
            } catch {
                lastError = "Core sent wiring this app can't read (update the app?): \(error)"
            }
        case CoreProps.pinStatus.id:
            do {
                let revision = try PinStatus(hex: raw).revision
                // wiring has no notify; a new revision is how we learn it changed.
                if let seen = wiringRevision, seen != revision, state.available.contains(CoreProps.wiring.id) {
                    issueRead(CoreProps.wiring.id)
                }
                wiringRevision = revision
            } catch {
                lastError = "Core sent unreadable pin status: \(error)"
            }
        case CoreProps.layers.id:
            decodeLayers()
        case CoreProps.layersRevision.id:
            guard let revision = Int(raw) else {
                lastError = "Core sent an unreadable layers revision: \"\(raw)\""
                return
            }
            if let seen = layersRevision, seen != revision, state.available.contains(CoreProps.layers.id) {
                issueRead(CoreProps.layers.id)
            }
            layersRevision = revision
        default:
            break
        }
    }

    /// Needs `documentation`, which names the summary's animation and blend mode indices.
    private func decodeLayers() {
        guard let raw = state.raw[CoreProps.layers.id], let documentation = state.documentation else { return }
        do {
            let summary = try LayerSummary(wire: raw, documentation: documentation)
            state.layerSummary = summary
            state.layerSummaryError = nil
            if case .preset = summary.source { state.ownLayerSummary = summary }
        } catch {
            state.layerSummary = nil
            state.layerSummaryError = error
            lastError = "Core sent a layer summary this app can't read (\(error)); showing one layer at a time."
        }
    }

    /// animationDocs pairs with documentation.animations by index, so a count mismatch
    /// would hand animations each other's docs.
    private func checkAnimationDocs() {
        guard let docs = state.animationDocs, let animations = state.documentation?.animations,
              docs.entries.count != animations.count else { return }
        state.animationDocs = nil
        lastError = "Core's animationDocs lists \(docs.entries.count) animations but its documentation lists \(animations.count); using the app's own animation table."
    }

    /// The firmware rejects invalid wiring silently, keeping its own; the
    /// read-back after a write is the only place that shows.
    private func confirmWiringWrite(_ raw: String) {
        guard let expected = expectedWiring else { return }
        expectedWiring = nil
        if WiringConverter.convert(raw) != expected {
            lastError = "The core rejected that wiring change and kept its previous wiring."
        }
    }

    /// Re-reads every property. Call on return to foreground: the link may
    /// have survived, but the device state may not have.
    public func refresh() {
        guard connection == .connected else { return }
        for id in state.available where !CoreProps.writeOnly.contains(id) { issueRead(id) }
    }

    private func issueRead(_ id: PropertyID) {
        outstandingReads[id, default: []].append(false)
        link.read(id)
    }

    /// Whether the response is stale. A response that nobody requested isn't.
    @discardableResult
    private func finishRead(of id: PropertyID) -> Bool {
        guard let stale = outstandingReads[id]?.first else { return false }
        outstandingReads[id]?.removeFirst()
        return stale
    }

    /// Whether a write that will change `id` on the core is throttled, queued or in flight.
    private func isWriting(_ id: PropertyID) -> Bool {
        throttled[id] != nil || inFlight?.covers(id) == true || queue.contains { $0.covers(id) }
    }

    // MARK: - Writes

    /// Optimistic write: state updates immediately, the device gets the
    /// latest value at most once per throttle interval, trailing-edge.
    public func set<C>(_ key: PropertyKey<C>, to value: C.ValueType) {
        let raw = C.unconvert(value)
        // Skipping equal values also stops color round-trip oscillation
        // (Color → native color re-quantizes by ±1).
        guard raw != state.raw[key.id] else { return }
        state.raw[key.id] = raw
        guard throttled[key.id] == nil else { return }
        let timer = Task { [throttle] in
            do { try await Task.sleep(for: throttle) } catch { return }  // cancelled: flushed or disconnected
            throttled[key.id] = nil
            queueLatest(key.id, name: key.name)
        }
        throttled[key.id] = (key.name, timer)
    }

    /// For the cursors (layer, preset), whose device-side change fans out to the
    /// per-layer props: write immediately, then refetch everything once acked.
    /// Edits still throttled go first, because they were made for the old cursor.
    /// Per-layer values read before the move describe the old layer, so the write holds them.
    public func select<C>(_ key: PropertyKey<C>, _ value: C.ValueType) {
        flushThrottled()
        write(key, value, holds: CoreProps.perLayer, then: { [weak self] in self?.refresh() })
    }

    /// Queues the value now, even when it equals the current one: after a cursor move,
    /// the current value may describe another layer.
    private func write<C>(_ key: PropertyKey<C>, _ value: C.ValueType, holds: [PropertyID] = [],
                          then: (@MainActor () -> Void)? = nil) {
        throttled.removeValue(forKey: key.id)?.timer.cancel()
        state.raw[key.id] = C.unconvert(value)
        queueLatest(key.id, name: key.name, holds: holds, then: then)
    }

    private func flushThrottled() {
        for (id, (name, timer)) in throttled {
            timer.cancel()
            queueLatest(id, name: name)
        }
        throttled = [:]
    }

    private func queueLatest(_ id: PropertyID, name: String, raw: String? = nil, holds: [PropertyID] = [],
                             then: (@MainActor () -> Void)? = nil) {
        guard let raw = raw ?? state.raw[id] else { return }
        queue.append(Write(id: id, name: name, raw: raw, holds: holds, then: then))
        if writer == nil {
            writer = Task { await drainQueue() }
        }
    }

    private func drainQueue() async {
        while !queue.isEmpty, connection == .connected {
            let write = queue.removeFirst()
            inFlight = write
            // The core answers in order, so reads requested before this write show the old value.
            for id in [write.id] + write.holds {
                outstandingReads[id] = outstandingReads[id]?.map { _ in true }
            }
            do {
                try await link.write(write.raw, to: write.id)
            } catch {
                inFlight = nil
                // Later writes may depend on this one (a cursor move), so they don't go either,
                // and neither do throttled edits, which would land on the old cursor.
                for (_, timer) in throttled.values { timer.cancel() }
                let dropped = queue.count + throttled.count
                queue = []
                throttled = [:]
                let unsent = switch dropped {
                case 0: ""
                case 1: " The change after it wasn't sent."
                default: " The \(dropped) changes after it weren't sent."
                }
                lastError = "Couldn't set \(write.name): \(error.localizedDescription).\(unsent)"
                refresh()  // show what the core kept
                break
            }
            inFlight = nil
            if write.id == CoreProps.wiring.id { expectedWiring = WiringConverter.convert(write.raw) }
            write.then?()
        }
        queue = []  // writes while disconnected are dropped; the reconnect re-reads everything
        writer = nil
    }

    // MARK: - Layers

    /// Points the per-layer properties at layer `slot` of the current preset. Until the
    /// core answers, they show that layer as the layer summary describes it.
    public func selectLayer(_ slot: Int) {
        guard state[CoreProps.layer] != slot || isWriting(CoreProps.layer.id) else { return }
        select(CoreProps.layer, slot)
        showCursorLayerFromSummary()
    }

    /// Switches the core to another preset. The per-layer properties show as loading until
    /// the core answers, rather than as the previous preset's layer.
    public func selectPreset(_ preset: Int) {
        select(CoreProps.preset, preset)
        if state.isAvailable(CoreProps.layers) {
            for id in CoreProps.perLayer { state.raw[id] = nil }
        }
    }

    /// Fills the first empty slot with Static and points the cursor at it. Returns the
    /// slot; nil while the stack is unknown or all ten layers are used.
    @discardableResult
    public func addLayer() -> Int? {
        guard let slot = state.ownLayers?.firstEmptySlot else { return nil }
        selectLayer(slot)
        write(CoreProps.animation, "Static")
        return slot
    }

    /// Empties layer `slot` (animation Nothing), leaving the cursor on it.
    public func removeLayer(_ slot: Int) {
        selectLayer(slot)
        editOwnLayers { $0.layers.removeAll { $0.index == slot } }
        write(CoreProps.animation, nothing, holds: [CoreProps.layers.id])
    }

    /// Moves layer `from` of the current preset to slot `to`, shifting the layers in
    /// between, as the firmware's layerMove does. Wiring and layer gates stay with
    /// their slot; `layerMoveNotice` says which wired controls now act on another layer.
    public func moveLayer(from: Int, to: Int) {
        let slots = 0 ..< CoreProps.layerCount
        precondition(slots.contains(from) && slots.contains(to), "layer move \(from) \(to) is out of range")
        guard from != to else { return }
        flushThrottled()  // edits made for the layers' old slots
        if let before = state.ownLayers {
            let after = before.moving(from: from, to: to)
            if let wiring = state[CoreProps.wiring], let docs = state.wiringDocs {
                layerMoveNotice = LayerSummary.wiringNotice(before: before, after: after, wiring: wiring, docs: docs)
            }
            editOwnLayers { $0 = after }
        }
        if state[CoreProps.layer] == from { state.raw[CoreProps.layer.id] = String(to) }
        showCursorLayerFromSummary()
        queueLatest(CoreProps.layerMove.id, name: "layer order", raw: "\(from) \(to)",
                    holds: [CoreProps.layers.id, CoreProps.layer.id] + CoreProps.perLayer,
                    then: { [weak self] in self?.refresh() })
    }

    /// The firmware's name for animation index 0.
    private var nothing: String { state.documentation?.animations.first ?? RenderLibrary.nothing }

    /// Applies an optimistic edit to the core's own layers, wherever the state holds them.
    private func editOwnLayers(_ edit: (inout LayerSummary) -> Void) {
        guard let own = state.ownLayers else { return }
        if state.layerSummary == own { edit(&state.layerSummary!) }
        edit(&state.ownLayerSummary!)
    }

    /// Shows the summary's values in the per-layer properties until the core's own
    /// arrive, so that a cursor move never shows the previous layer's settings.
    private func showCursorLayerFromSummary() {
        guard let slot = state[CoreProps.layer], let own = state.ownLayers else { return }
        guard let look = own.layer(at: slot)?.look else {
            for id in CoreProps.perLayer { state.raw[id] = nil }
            state.raw[CoreProps.animation.id] = nothing
            return
        }
        func wire(_ c: PixelColor) -> String { "\(c.r) \(c.g) \(c.b)" }
        state.raw[CoreProps.animation.id] = look.animation
        state.raw[CoreProps.blendMode.id] = look.blendMode
        state.raw[CoreProps.color.id] = wire(look.color1)
        state.raw[CoreProps.color2.id] = wire(look.color2)
        state.raw[CoreProps.speed.id] = DoubleConverter.unconvert(look.speed)
        state.raw[CoreProps.tau.id] = DoubleConverter.unconvert(look.tau)
        state.raw[CoreProps.phi.id] = DoubleConverter.unconvert(look.phi)
        state.raw[CoreProps.beatSync.id] = look.beatSynced ? "1" : "0"
    }
}
