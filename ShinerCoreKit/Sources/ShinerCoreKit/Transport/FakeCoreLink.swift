import Foundation

/// A scripted `CoreLink` for previews and tests: connects instantly,
/// acks writes, and echoes reads from an in-memory property table. Like the
/// firmware, a `wiring` write bumps the pinStatus revision and notifies it.
@MainActor
public final class FakeCoreLink: CoreLink {
    public let events: AsyncStream<CoreLinkEvent>
    private let emit: AsyncStream<CoreLinkEvent>.Continuation

    /// The fake device's property table.
    public var values: [PropertyID: String]
    /// Every write that reached the "device", in order.
    public private(set) var written: [(id: PropertyID, raw: String)] = []
    /// Every read request, in order.
    public private(set) var readRequests: [PropertyID] = []
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
    /// When true, `wiring` writes are acked but leave the stored wiring as
    /// it was, like the firmware rejecting an invalid wiring.
    public var rejectWiringWrites = false
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
        if !(id == CoreProps.wiring.id && rejectWiringWrites) { values[id] = raw }
        if id == CoreProps.wiring.id, let status = values[CoreProps.pinStatus.id].flatMap(PinStatusConverter.convert) {
            let bumped = PinStatus(revision: status.revision &+ 1, closed: status.closed,
                                   claimed: status.claimed, positions: status.positions).hex
            values[CoreProps.pinStatus.id] = bumped
            emit.yield(.valueChanged(CoreProps.pinStatus.id, bumped))
        }
    }

    public func read(_ id: PropertyID) {
        readRequests.append(id)
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

    /// The boards that `demo(board:)` can pose as.
    public enum DemoBoard: String, CaseIterable, Sendable {
        case atomEcho = "atom-echo", atomLite = "atom-lite", atomS3Lite = "atoms3-lite"
    }

    /// What the firmware's buildDocumentationJSON (Comms.h) sends: the names in
    /// ShinyTypes.cpp and Animations.cpp, in firmware order.
    static let demoDocumentation = #"{"blendModes":["Add","Subtract","Add Wrap","Subtract Wrap","Multiply","Dissolve","Average","Set","Screen","Lighten","Darken","Difference","Overlay","Color Dodge"],"animations":["Nothing","Static","Opposing Waves","Single Wave","Breathe","Rainbow","Comet","Scanner","Twinkle","Theater Chase","Color Wipe","Gradient Pulse","Sparkle","Beat Pulse"],"ledColorOrders":["RGB","GRB","BGR"]}"#

    /// What the firmware's animationDocsJSON (ShinyTypes.cpp) sends for those animations.
    static let demoAnimationDocs = #"[[0],[1],[2,"Wave length","Counter-wave length"],[1,"Wave length","Phase"],[2],[0,"Rainbows","Drift speed"],[2,"Tail length","Head width"],[2,"Width","Glow"],[2,"Density","Twinkle speed"],[2,"Spacing","Group size"],[2,"Wipe time"],[2,"Sharpness","Repeats"],[2,"Flash length","Density"],[1]]"#

    /// A populated fake for previews, wired like the given board might be. Values
    /// are in the firmware's wire formats, so screenshots show what a real core sends.
    public static func demo(board: DemoBoard = .atomEcho) -> FakeCoreLink {
        let link = FakeCoreLink(values: [
            CoreProps.mode.id: "1",
            CoreProps.brightness.id: "180",
            CoreProps.name.id: "Nevyn",
            CoreProps.color.id: "255 40 120",
            CoreProps.color2.id: "0 80 255",
            CoreProps.speed.id: "2.500",
            CoreProps.tau.id: "1.000",
            CoreProps.phi.id: "0.500",
            CoreProps.layer.id: "0",
            CoreProps.preset.id: "1",
            CoreProps.bootPreset.id: "0",
            CoreProps.animation.id: "Gradient Pulse",
            CoreProps.beatSync.id: "0",
            CoreProps.blendMode.id: "Add",
            CoreProps.ledOrder.id: "GRB",
            CoreProps.ledCount.id: "144",
            CoreProps.mic.id: "1",
            CoreProps.mesh.id: "1",
            CoreProps.meshShow.id: "1",
            CoreProps.meshGroup.id: "kidsville",
            CoreProps.carouselBeats.id: "8",
            CoreProps.maxCurrent.id: "0",
            CoreProps.documentation.id: demoDocumentation,
            CoreProps.animationDocs.id: demoAnimationDocs,
        ])
        let targets = #""targets":["brightness","speed","tau","phi","color1.r","color1.g","color1.b","color1.h","color1.s","color1.v","color2.r","color2.g","color2.b","color2.h","color2.s","color2.v"]"#
        let atomPins = #""pins":["G21","G25","G22","G19","G23","G33","G26","G32"]"#
        switch board {
        case .atomEcho:
            link.values[CoreProps.wiringDocs.id] = #"{"board":"atom-echo",\#(atomPins),"frontButton":"G39","analog":["G32"],"led":["G26","G32"],"claims":{"G19":"speaker","G22":"speaker","G23":"microphone","G33":"microphone"},\#(targets)}"#
            link.values[CoreProps.wiring.id] = #"{"G21":{"button":"nextPreset"},"G25":{"switch":"lightsOff"},"G26":{"leds":true},"G32":{"knob":"brightness","min":0,"max":255},"G39":{"button":"nextPreset"}}"#
            link.values[CoreProps.pinStatus.id] = "07013c9e"  // G21 pressed, knob at 62%
        case .atomLite:
            link.values[CoreProps.wiringDocs.id] = #"{"board":"atom-lite",\#(atomPins),"frontButton":"G39","analog":["G33","G32"],"led":["G26","G32"],"claims":{"G23":"microphone","G33":"microphone"},\#(targets)}"#
            link.values[CoreProps.wiring.id] = #"{"G21":{"button":"nextPreset"},"G25":{"switch":"lightsOff"},"G22":{"switch":"preset","preset":0},"G19":{"switch":"preset","preset":1},"G23":{"switch":"preset","preset":2},"G33":{"knob":"color1.h","layer":2,"min":0,"max":255},"G26":{"leds":true},"G32":{"leds":true},"G39":{"button":"toggleLights"}}"#
            link.values[CoreProps.pinStatus.id] = "0304004dff"  // G22 closed, hue knob at 30%
            link.values[CoreProps.mic.id] = "0"  // frees G23 and G33
            link.values[CoreProps.preset.id] = "0"  // held by G22
        case .atomS3Lite:
            link.values[CoreProps.wiringDocs.id] = #"{"board":"atoms3-lite","pins":["G39","G38","G5","G6","G7","G8","G2","G1"],"frontButton":"G41","analog":["G5","G6","G7","G8","G2","G1"],"led":["G2","G1"],"claims":{},\#(targets)}"#
            link.values[CoreProps.wiring.id] = #"{"G39":{"button":"nextPreset"},"G38":{"switch":"lightsOff"},"G5":{"switch":"preset","preset":0},"G6":{"switch":"preset","preset":1},"G7":{"switch":"preset","preset":2},"G8":{"switch":"preset","preset":3},"G2":{"leds":true},"G1":{"leds":true},"G41":{"button":"nextPreset"}}"#
            link.values[CoreProps.pinStatus.id] = "010000ffffffffffff"
        }
        return link
    }
}
