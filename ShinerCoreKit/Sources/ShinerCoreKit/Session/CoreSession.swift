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
    }

    public private(set) var state = CoreState()
    public private(set) var connection: ConnectionState = .connecting
    /// Settable so the UI can dismiss it.
    public var lastError: String?

    @ObservationIgnored private let link: any CoreLink
    @ObservationIgnored private let throttle: Duration
    /// Props with an unsent or in-flight write; inbound reads for them are
    /// stale by definition and dropped (stops refetches yanking sliders mid-drag).
    @ObservationIgnored private var dirty: Set<PropertyID> = []
    @ObservationIgnored private var writeTasks: [PropertyID: Task<Void, Never>] = [:]

    public init(link: any CoreLink, throttle: Duration = .milliseconds(100)) {
        self.link = link
        self.throttle = throttle
    }

    /// Runs the connection for the lifetime of the calling task.
    /// Cancellation disconnects; back = disconnect. While the task lives,
    /// a lost link reconnects automatically: `connect()` is a standing
    /// intent that completes whenever the device reappears.
    public func run() async {
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
            link.readAll()
        case .disconnected(let reason):
            connection = .reconnecting
            if let reason { lastError = reason.description }
            dirty = []
            link.connect()
        case .becameAvailable(let id):
            state.available.insert(id)
        case .valueRead(let id, let raw):
            guard !dirty.contains(id) else { return }
            state.raw[id] = raw
            if id == CoreProps.documentation.id {
                state.documentation = DocumentationConverter.convert(raw)
                if state.documentation == nil {
                    lastError = "Core sent unparseable documentation"
                }
            }
        case .readFailed(let id, let error):
            lastError = "Couldn't read \(id): \(error.description)"
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
        dirty.remove(id)
    }

    /// Re-reads every property. Call on return to foreground: the link may
    /// have survived, but the device state may not have.
    public func refresh() {
        guard connection == .connected else { return }
        link.readAll()
    }

    /// For props whose device-side change fans out to other props
    /// (layer, preset): write immediately, then refetch everything once acked.
    public func select<C>(_ key: PropertyKey<C>, _ value: C.ValueType) {
        let raw = C.unconvert(value)
        state.raw[key.id] = raw
        Task {
            do {
                try await link.write(raw, to: key.id)
                link.readAll()
            } catch {
                lastError = "Couldn't set \(key.name): \(error.localizedDescription)"
            }
        }
    }
}
