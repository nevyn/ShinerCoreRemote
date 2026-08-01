import Foundation

/// A scripted `CoreLink` for previews and tests: connects instantly,
/// acks writes, and echoes reads from an in-memory property table.
@MainActor
public final class FakeCoreLink: CoreLink {
    public let events: AsyncStream<CoreLinkEvent>
    private let emit: AsyncStream<CoreLinkEvent>.Continuation

    /// The fake device's property table.
    public var values: [PropertyID: String]
    /// Every write that reached the "device", in order.
    public private(set) var written: [(id: PropertyID, raw: String)] = []
    public private(set) var connectCount = 0
    public private(set) var disconnectCount = 0
    /// While false, `connect()` becomes a pending intent — like the real
    /// standing CoreBluetooth connect — completed by `becomeReachable()`.
    public private(set) var reachable = true
    /// When set, writes fail with this error.
    public var writeError: CoreLinkError?
    /// When true, `read` responses queue up until `deliverPendingReads()`,
    /// capturing the value at request time — models the device answering
    /// serially, so a response can be stale by the time it arrives.
    public var deferReads = false
    private var pendingConnect = false
    private var deferredReads: [(id: PropertyID, raw: String?)] = []

    public init(values: [PropertyID: String] = [:]) {
        self.values = values
        (events, emit) = AsyncStream.makeStream()
    }

    public func connect() {
        connectCount += 1
        if reachable {
            deliverConnection()
        } else {
            pendingConnect = true
        }
    }

    public func becomeUnreachable() {
        reachable = false
        emit.yield(.disconnected(reason: nil))
    }

    public func becomeReachable() {
        reachable = true
        if pendingConnect {
            pendingConnect = false
            deliverConnection()
        }
    }

    private func deliverConnection() {
        for id in values.keys { emit.yield(.becameAvailable(id)) }
        emit.yield(.connected)
    }

    public func disconnect() {
        disconnectCount += 1
        pendingConnect = false
    }

    public func write(_ raw: String, to id: PropertyID) async throws {
        if let writeError { throw writeError }
        guard reachable else { throw CoreLinkError("Disconnected") }
        written.append((id, raw))
        values[id] = raw
    }

    public func read(_ id: PropertyID) {
        if deferReads {
            deferredReads.append((id, values[id]))
        } else {
            deliver(id: id, raw: values[id])
        }
    }

    public func deliverPendingReads() {
        for (id, raw) in deferredReads { deliver(id: id, raw: raw) }
        deferredReads = []
    }

    private func deliver(id: PropertyID, raw: String?) {
        if let raw {
            emit.yield(.valueRead(id, raw))
        } else {
            emit.yield(.readFailed(id, CoreLinkError("No such property")))
        }
    }

    /// Test/preview hook: push an arbitrary event, e.g. `.disconnected` to
    /// simulate link loss or `.valueRead` to simulate a device-side change.
    public func inject(_ event: CoreLinkEvent) {
        emit.yield(event)
    }

    /// A populated fake for previews.
    public static func demo() -> FakeCoreLink {
        FakeCoreLink(values: [
            CoreProps.mode.id: "1",
            CoreProps.brightness.id: "180",
            CoreProps.name.id: "Nevyn",
            CoreProps.color.id: "255 40 120",
            CoreProps.color2.id: "0 80 255",
            CoreProps.speed.id: "2.5",
            CoreProps.tau.id: "1.0",
            CoreProps.phi.id: "0.5",
            CoreProps.layer.id: "0",
            CoreProps.preset.id: "1",
            CoreProps.animation.id: "rainbow",
            CoreProps.beatSync.id: "0",
            CoreProps.blendMode.id: "add",
            CoreProps.ledOrder.id: "GRB",
            CoreProps.ledCount.id: "144",
            CoreProps.mic.id: "1",
            CoreProps.mesh.id: "1",
            CoreProps.meshShow.id: "1",
            CoreProps.carouselBeats.id: "8",
            CoreProps.documentation.id: #"{"blendModes":["add","multiply","overwrite"],"animations":["rainbow","pulse","sparkle","solid"],"ledColorOrders":["RGB","GRB","BGR"]}"#,
        ])
    }
}
