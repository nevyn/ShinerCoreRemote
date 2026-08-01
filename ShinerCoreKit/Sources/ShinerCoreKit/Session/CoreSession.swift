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

    @ObservationIgnored private let link: any CoreLink
    @ObservationIgnored private let throttle: Duration
    /// Props whose optimistic local value must not be clobbered: an unsent
    /// or in-flight write, or reads requested before that write completed
    /// whose responses are stale by definition. Cleared per-prop once no
    /// writer is active and no counted reads are outstanding.
    @ObservationIgnored private var dirty: Set<PropertyID> = []
    /// Outstanding read requests per prop: exactly one valueRead/readFailed
    /// event comes back per request, so this counts in-flight staleness.
    @ObservationIgnored private var pendingReads: [PropertyID: Int] = [:]
    @ObservationIgnored private var writeTasks: [PropertyID: Task<Void, Never>] = [:]
    @ObservationIgnored private var hasRun = false

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
            dirty = []
            pendingReads = [:]
            state.available = []  // firmware may differ after reconnect; rediscovery repopulates
            link.connect()
        case .incompatible(let reason):
            connection = .failed(reason.description)
        case .becameAvailable(let id):
            state.available.insert(id)
        case .valueRead(let id, let raw):
            let wasDirty = dirty.contains(id)  // before finishRead may settle it
            finishRead(of: id)
            guard !wasDirty else { return }  // stale; the acked optimistic value stands
            applyDeviceValue(id, raw)
        case .valueChanged(let id, let raw):
            // A notification: another central, cursor fanout, or our own
            // write echoing back. No read bookkeeping — nothing was requested.
            guard !dirty.contains(id) else { return }
            applyDeviceValue(id, raw)
        case .readFailed(let id, let error):
            finishRead(of: id)
            lastError = "Couldn't read \(id): \(error.description)"
        }
    }

    private func applyDeviceValue(_ id: PropertyID, _ raw: String) {
        guard state.raw[id] != raw else { return }
        state.raw[id] = raw
        if id == CoreProps.documentation.id {
            state.documentation = DocumentationConverter.convert(raw)
            if state.documentation == nil {
                lastError = "Core sent unparseable documentation"
            }
        }
    }

    /// Re-reads every property. Call on return to foreground: the link may
    /// have survived, but the device state may not have.
    public func refresh() {
        guard connection == .connected else { return }
        for id in state.available { issueRead(id) }
    }

    private func issueRead(_ id: PropertyID) {
        pendingReads[id, default: 0] += 1
        link.read(id)
    }

    private func finishRead(of id: PropertyID) {
        pendingReads[id] = max(0, (pendingReads[id] ?? 0) - 1)
        cleanIfSettled(id)
    }

    private func cleanIfSettled(_ id: PropertyID) {
        if writeTasks[id] == nil, pendingReads[id, default: 0] == 0 {
            dirty.remove(id)
        }
    }

    /// Optimistic write: state updates immediately, the device gets the
    /// latest value at most once per throttle interval, trailing-edge.
    public func set<C>(_ key: PropertyKey<C>, to value: C.ValueType) {
        let raw = C.unconvert(value)
        // Skipping equal values also stops color round-trip oscillation
        // (Color → native color re-quantizes by ±1).
        guard raw != state.raw[key.id] else { return }
        state.raw[key.id] = raw
        dirty.insert(key.id)
        guard writeTasks[key.id] == nil else { return }
        writeTasks[key.id] = Task {
            await drainWrites(of: key.id, name: key.name)
        }
    }

    private func drainWrites(of id: PropertyID, name: String) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: throttle)  // cancellation caught by loop guard
            guard connection == .connected, let raw = state.raw[id] else { break }
            do {
                try await link.write(raw, to: id)
            } catch {
                lastError = "Couldn't set \(name): \(error.localizedDescription)"
                break
            }
            if state.raw[id] == raw { break }  // caught up with the user
        }
        writeTasks[id] = nil
        cleanIfSettled(id)
    }

    /// For props whose device-side change fans out to other props
    /// (layer, preset): write immediately, then refetch everything once acked.
    public func select<C>(_ key: PropertyKey<C>, _ value: C.ValueType) {
        let raw = C.unconvert(value)
        state.raw[key.id] = raw
        dirty.insert(key.id)  // pre-write reads in flight must not flick the picker back
        Task {
            do {
                try await link.write(raw, to: key.id)
                refresh()
            } catch {
                lastError = "Couldn't set \(key.name): \(error.localizedDescription)"
            }
            cleanIfSettled(key.id)
        }
    }
}
