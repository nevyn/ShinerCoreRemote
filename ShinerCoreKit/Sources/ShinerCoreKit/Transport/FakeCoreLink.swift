import Foundation

/// A `CoreLink` backed by a small model of the firmware, for previews, tests and demo
/// mode: connects instantly and acks writes. Like the firmware, it keeps five presets of
/// ten layers and serves the per-layer properties of the layer under the `layer` and
/// `preset` cursors; moving a cursor republishes them. `layers`, `layerOpacities` and
/// `layersRevision` derive from the model, `layerMove` moves layers per the contract, and
/// a `wiring` write bumps the pinStatus revision and notifies it.
@MainActor
public final class FakeCoreLink: CoreLink {
    public let events: AsyncStream<CoreLinkEvent>
    private let emit: AsyncStream<CoreLinkEvent>.Continuation

    /// The fake device's readable properties as the firmware would answer reads now.
    /// Assigning routes each value into the model: per-layer properties land in the
    /// layer under the cursors, and the cursors move. Removing a key hides that property,
    /// as on older firmware. `layers`, `layerOpacities` and `layersRevision` always derive
    /// from the model; assigning `layers` or `layersRevision` exposes the layer summary,
    /// removing one hides it. Removing `layerOpacities` alone poses as firmware that
    /// predates opacity.
    public var values: [PropertyID: String] {
        get {
            Dictionary(uniqueKeysWithValues: exposed.compactMap { id in value(of: id).map { (id, $0) } })
        }
        set {
            let old = values
            for id in exposed.subtracting(newValue.keys).subtracting(CoreProps.writeOnly) {
                if Self.summaryProps.contains(id) {
                    exposesLayerSummary = false
                } else {
                    exposed.remove(id)
                }
            }
            // Cursors first, so that changed per-layer values land in the layer they now point at.
            let isCursor = { (id: PropertyID) in id == CoreProps.preset.id || id == CoreProps.layer.id }
            let changes = newValue.filter { old[$0.key] != $0.value }
            for (id, raw) in changes.filter({ isCursor($0.key) }) + changes.filter({ !isCursor($0.key) }) {
                if Self.summaryProps.contains(id) {
                    exposesLayerSummary = true
                } else {
                    exposed.insert(id)
                    store(raw, for: id)
                }
            }
            publishLayers(notify: false)
        }
    }

    /// `presets[p][l]` holds the per-layer properties (`CoreProps.perLayer`) of layer `l`
    /// of preset `p`.
    public private(set) var presets: [[[PropertyID: String]]] =
        Array(repeating: Array(repeating: FakeCoreLink.emptyLayer, count: CoreProps.layerCount), count: CoreProps.presetCount)
    public private(set) var presetCursor = 0
    public private(set) var layerCursor = 0
    /// Layer gates by slot; false closes the gate, as a switch or button does.
    public var gates = Array(repeating: true, count: CoreProps.layerCount) {
        didSet { publishLayers(notify: true) }
    }
    /// While non-nil, the mesh carousel plays a neighbor's preset: these layers (each
    /// keyed like `presets`), and `layers` says `M`.
    public var neighborLayers: [[PropertyID: String]]? {
        didSet { publishLayers(notify: true) }
    }
    /// False poses as firmware that predates the layer summary; true also exposes `layerOpacities`.
    public var exposesLayerSummary: Bool {
        get { exposed.contains(CoreProps.layers.id) }
        set {
            if newValue {
                exposed.formUnion(Self.summaryProps + [CoreProps.layerOpacities.id])
            } else {
                exposed.subtract(Self.summaryProps + [CoreProps.layerOpacities.id])
            }
        }
    }

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
    /// False holds back the per-layer notifications after a cursor move, as the
    /// firmware's flush limiter does for up to half a second.
    public var republishesCursorLayer = true
    /// Reads of these properties fail with the given error.
    public var readErrors: [PropertyID: CoreLinkError] = [:]
    /// Writes to these properties fail with the given error.
    public var writeErrors: [PropertyID: CoreLinkError] = [:]
    /// When true, `read` responses queue up until `deliverPendingReads()`,
    /// capturing the value at request time — models the device answering
    /// serially, so a response can be stale by the time it arrives.
    public var deferReads = false
    /// When true, `wiring` writes are acked but leave the stored wiring as
    /// it was, like the firmware rejecting an invalid wiring.
    public var rejectWiringWrites = false

    private var table: [PropertyID: String] = [:]
    private var exposed: Set<PropertyID> = []
    private var layersRevision = 0
    private var publishedLayers = ""
    private var publishedOpacities = ""
    private var pendingConnect = false
    private var deferredReads: [(id: PropertyID, raw: String?)] = []

    private static let summaryProps: Set<PropertyID> = [CoreProps.layers.id, CoreProps.layersRevision.id, CoreProps.layerMove.id]

    /// A slot whose animation is Nothing.
    public static let emptyLayer: [PropertyID: String] = [
        CoreProps.animation.id: "Nothing", CoreProps.blendMode.id: "Add",
        CoreProps.color.id: "255 255 255", CoreProps.color2.id: "0 0 0",
        CoreProps.speed.id: "1.000", CoreProps.tau.id: "1.000", CoreProps.phi.id: "1.000",
        CoreProps.beatSync.id: "0", CoreProps.opacity.id: "1.000",
    ]

    /// A layer's per-layer properties in the firmware's wire formats.
    public static func layer(_ animation: String, blend: String = "Add", color: String, color2: String = "0 0 0",
                             speed: Double, tau: Double = 1, phi: Double = 1, beatSync: Bool = false,
                             opacity: Double = 1) -> [PropertyID: String] {
        func fixed(_ value: Double) -> String { String(format: "%.3f", value) }
        return [
            CoreProps.animation.id: animation, CoreProps.blendMode.id: blend,
            CoreProps.color.id: color, CoreProps.color2.id: color2,
            CoreProps.speed.id: fixed(speed), CoreProps.tau.id: fixed(tau), CoreProps.phi.id: fixed(phi),
            CoreProps.beatSync.id: beatSync ? "1" : "0", CoreProps.opacity.id: fixed(opacity),
        ]
    }

    public init(values: [PropertyID: String] = [:]) {
        (events, emit) = AsyncStream.makeStream()
        self.values = values
    }

    /// Replaces a layer of a preset, as if edited on the device.
    public func setLayer(_ layer: [PropertyID: String], preset: Int, slot: Int) {
        presets[preset][slot] = layer
        if (preset, slot) == (presetCursor, layerCursor) { republishCursorLayer() }
        publishLayers(notify: true)
    }

    private func republishCursorLayer() {
        guard republishesCursorLayer else { return }
        for id in CoreProps.perLayer where exposed.contains(id) {
            emit.yield(.valueChanged(id, presets[presetCursor][layerCursor][id]!))
        }
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
        for id in exposed { emit.yield(.becameAvailable(id)) }
        emit.yield(.connected)
    }

    public func disconnect() {
        disconnectCount += 1
        pendingConnect = false
    }

    public func write(_ raw: String, to id: PropertyID) async throws {
        if let error = writeError ?? writeErrors[id] { throw error }
        guard reachable else { throw CoreLinkError("Disconnected") }
        written.append((id, raw))
        switch id {
        case CoreProps.layerMove.id:
            move(raw)
        case CoreProps.layers.id, CoreProps.layersRevision.id, CoreProps.layerOpacities.id:
            break  // read-only
        case CoreProps.wiring.id:
            if !rejectWiringWrites { table[id] = raw }
            if let status = table[CoreProps.pinStatus.id].flatMap(PinStatusConverter.convert) {
                let bumped = PinStatus(revision: status.revision &+ 1, closed: status.closed,
                                       claimed: status.claimed, positions: status.positions).hex
                table[CoreProps.pinStatus.id] = bumped
                emit.yield(.valueChanged(CoreProps.pinStatus.id, bumped))
            }
        default:
            let cursorBefore = (presetCursor, layerCursor)
            store(raw, for: id)
            if (presetCursor, layerCursor) != cursorBefore { republishCursorLayer() }
        }
        publishLayers(notify: true)
        // A write is a round trip: what the core notified meanwhile reaches the session before the ack.
        await Task.yield()
    }

    /// Out-of-range cursors are ignored, like the firmware does.
    private func store(_ raw: String, for id: PropertyID) {
        switch id {
        case CoreProps.preset.id:
            if let preset = Int(raw), (0 ..< CoreProps.presetCount).contains(preset) { presetCursor = preset }
        case CoreProps.layer.id:
            if let layer = Int(raw), (0 ..< CoreProps.layerCount).contains(layer) { layerCursor = layer }
        case _ where CoreProps.perLayer.contains(id):
            presets[presetCursor][layerCursor][id] = raw
        default:
            table[id] = raw
        }
    }

    /// `FROM TO`: remove the layer at FROM, insert it at TO; a cursor on FROM follows it.
    private func move(_ raw: String) {
        let fields = raw.split(separator: " ").compactMap { Int($0) }
        let slots = 0 ..< CoreProps.layerCount
        guard fields.count == 2, slots.contains(fields[0]), slots.contains(fields[1]) else { return }
        let (from, to) = (fields[0], fields[1])
        presets[presetCursor].insert(presets[presetCursor].remove(at: from), at: to)
        if layerCursor == from { layerCursor = to }
    }

    private func value(of id: PropertyID) -> String? {
        switch id {
        case CoreProps.preset.id: String(presetCursor)
        case CoreProps.layer.id: String(layerCursor)
        case CoreProps.layers.id: publishedLayers
        case CoreProps.layerOpacities.id: publishedOpacities
        case CoreProps.layersRevision.id: String(layersRevision)
        case CoreProps.layerMove.id: nil
        case _ where CoreProps.perLayer.contains(id): presets[presetCursor][layerCursor][id]
        default: table[id]
        }
    }

    /// Bumps the revision whenever `layers` or `layerOpacities` would read differently, like the firmware.
    private func publishLayers(notify: Bool) {
        let (wire, opacities) = (layersWire, opacitiesWire)
        guard wire != publishedLayers || opacities != publishedOpacities else { return }
        (publishedLayers, publishedOpacities) = (wire, opacities)
        layersRevision = (layersRevision + 1) % 65536
        if notify, exposesLayerSummary {
            emit.yield(.valueChanged(CoreProps.layersRevision.id, String(layersRevision)))
        }
    }

    /// The `layers` value: the firmware's compact format, docs/ble-comms.md. Layers whose
    /// names the `documentation` value doesn't list are left out.
    private var layersWire: String {
        let docs = table[CoreProps.documentation.id].flatMap { try? Documentation(json: $0) } ?? Documentation()
        let header = neighborLayers == nil ? "P \(presetCursor)" : "M"
        let lines = (neighborLayers ?? presets[presetCursor]).enumerated().compactMap { slot, layer -> String? in
            guard let animation = layer[CoreProps.animation.id].flatMap(docs.animations.firstIndex(of:)), animation != 0,
                  let blend = layer[CoreProps.blendMode.id].flatMap(docs.blendModes.firstIndex(of:)) else { return nil }
            func hex(_ id: PropertyID) -> String { layer[id].flatMap(PixelColor.init(wire:))?.hex ?? "000000" }
            func compact(_ id: PropertyID) -> String { Self.compact(layer[id], default: 0) }
            return [String(slot), String(animation), String(blend), hex(CoreProps.color.id), hex(CoreProps.color2.id),
                    compact(CoreProps.speed.id), compact(CoreProps.tau.id), compact(CoreProps.phi.id),
                    layer[CoreProps.beatSync.id] == "1" ? "1" : "0", gates[slot] ? "1" : "0"].joined(separator: " ")
        }
        return ([header] + lines).joined(separator: "\n")
    }

    /// The `layerOpacities` value: every slot of what `layers` describes, empty ones too.
    private var opacitiesWire: String {
        let layers = neighborLayers ?? presets[presetCursor]
        return (0 ..< CoreProps.layerCount).map { slot in
            Self.compact(layers.indices.contains(slot) ? layers[slot][CoreProps.opacity.id] : nil, default: 1)
        }.joined(separator: " ")
    }

    /// The summary's float format: at most three decimals, trailing zeros and point dropped.
    nonisolated private static func compact(_ raw: String?, default fallback: Double) -> String {
        var s = String(format: "%.3f", raw.flatMap(Double.init) ?? fallback)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    public func read(_ id: PropertyID) {
        readRequests.append(id)
        if let error = readErrors[id] {
            emit.yield(.readFailed(id, error))
            return
        }
        let raw = exposed.contains(id) ? value(of: id) : nil
        if deferReads {
            deferredReads.append((id, raw))
        } else {
            deliver(id: id, raw: raw)
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
    nonisolated static let demoDocumentation = #"{"blendModes":["Add","Subtract","Add Wrap","Subtract Wrap","Multiply","Dissolve","Average","Set","Screen","Lighten","Darken","Difference","Overlay","Color Dodge"],"animations":["Nothing","Static","Opposing Waves","Single Wave","Breathe","Rainbow","Comet","Scanner","Twinkle","Theater Chase","Color Wipe","Gradient Pulse","Sparkle","Beat Pulse"],"ledColorOrders":["RGB","GRB","BGR"]}"#

    /// What the firmware's animationDocsJSON (ShinyTypes.cpp) sends for those animations.
    nonisolated static let demoAnimationDocs = #"[[0],[1],[2,"Wave length","Counter-wave length"],[1,"Wave length","Phase"],[2],[0,"Rainbows","Drift speed"],[2,"Tail length","Head width"],[2,"Width","Glow"],[2,"Density","Twinkle speed"],[2,"Spacing","Group size"],[2,"Wipe time"],[2,"Sharpness","Repeats"],[2,"Flash length","Density"],[1]]"#

    /// A populated fake for previews, wired like the given board might be. Values
    /// are in the firmware's wire formats, so screenshots show what a real core sends.
    /// A populated fake for previews, wired like the given board might be. Values
    /// are in the firmware's wire formats, so screenshots show what a real core sends.
    /// Preset 1, under the cursor, stacks Comet (Screen) and Sparkle on Gradient Pulse.
    public static func demo(board: DemoBoard = .atomEcho) -> FakeCoreLink {
        let link = FakeCoreLink(values: [
            CoreProps.mode.id: "1",
            CoreProps.brightness.id: "180",
            CoreProps.name.id: "Nevyn",
            CoreProps.bootPreset.id: "0",
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
        let stacks: [[[PropertyID: String]]] = [
            [layer("Breathe", color: "255 115 25", color2: "153 0 76", speed: 4)],
            [layer("Gradient Pulse", color: "255 40 120", color2: "0 80 255", speed: 2.5, tau: 10, phi: 4),
             layer("Comet", blend: "Screen", color: "255 255 255", speed: 1.8, tau: 3, phi: 2),
             layer("Sparkle", color: "255 230 153", speed: 1, tau: 4, phi: 3)],
            [layer("Scanner", color: "255 0 0", speed: 1.5, tau: 4, phi: 3)],
            [layer("Twinkle", color: "178 217 255", color2: "255 204 102", speed: 1, tau: 4, phi: 1)],
            [layer("Theater Chase", color: "0 255 128", speed: 0.8, tau: 4, phi: 2)],
        ]
        for (preset, stack) in stacks.enumerated() {
            for (slot, layer) in stack.enumerated() { link.presets[preset][slot] = layer }
        }
        link.presetCursor = 1
        link.exposed.formUnion(CoreProps.perLayer + [CoreProps.preset.id, CoreProps.layer.id])
        link.exposesLayerSummary = true
        link.publishLayers(notify: false)
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
