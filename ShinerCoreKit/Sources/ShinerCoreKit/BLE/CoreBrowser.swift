import CoreBluetooth
import Observation
import os

public struct DiscoveredCore: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

/// Owns the CBCentralManager: scanning, discovery, and vending sessions.
/// Central-level delegate callbacks for a connected core are forwarded to
/// its `BLECoreLink`.
@Observable @MainActor
public final class CoreBrowser: NSObject {
    /// The simulated core behind "Try the demo core": `makeSession(for:)` gives it a
    /// session over a fresh `FakeCoreLink.demo()`, so every visit starts from the same
    /// state and nothing persists. Never in `discovered`, never has signal bars.
    public let demoCore = DiscoveredCore(id: UUID(uuidString: "D3E0C0DE-5817-4E2C-9A1B-000000000000")!, name: "Demo core")
    /// Nearby cores in order of discovery.
    public private(set) var discovered: [DiscoveredCore] = []
    public private(set) var isBluetoothAvailable = false
    /// Signal bars (0-3, see `SignalMeter`) per discovered core, by id. Kept out of
    /// `DiscoveredCore` so that a changing RSSI doesn't change the list's identity.
    public private(set) var signalBars: [UUID: Int] = [:]

    @ObservationIgnored private let usesBluetooth: Bool
    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var links: [UUID: WeakLink] = [:]
    @ObservationIgnored private var meters: [UUID: SignalMeter] = [:]
    @ObservationIgnored private var wantsScan = false
    @ObservationIgnored private var previewLinkFactory: ((DiscoveredCore) -> any CoreLink)?
    @ObservationIgnored private let log = Logger(subsystem: "jpg.nevyn.shinerconf", category: "browser")

    private struct WeakLink { weak var link: BLECoreLink? }

    /// Bluetooth starts on first use (`startScanning()` or a session for a nearby core),
    /// so that a browser that only serves the demo core never touches it.
    public override init() {
        usesBluetooth = true
        super.init()
    }

    /// For previews and the `-demo` launch arguments: canned cores at fixed RSSIs (dBm) and
    /// no Bluetooth; their sessions come from `linkFactory` (typically
    /// `{ _ in FakeCoreLink.demo() }`). `demoCore` still gets its own fresh demo.
    public init(previewCores: [(core: DiscoveredCore, rssi: Int)], linkFactory: ((DiscoveredCore) -> any CoreLink)? = nil) {
        discovered = previewCores.map(\.core)
        meters = Dictionary(uniqueKeysWithValues: previewCores.compactMap { core, rssi in
            SignalMeter(rssi: rssi).map { (core.id, $0) }
        })
        signalBars = meters.mapValues(\.bars)
        isBluetoothAvailable = true
        previewLinkFactory = linkFactory
        usesBluetooth = false
        super.init()
    }

    public func startScanning() {
        guard usesBluetooth else { return }
        wantsScan = true
        _ = liveCentral  // scans once it reports poweredOn
        scanIfPossible()
    }

    public func stopScanning() {
        wantsScan = false
        central?.stopScan()
    }

    /// Forgets cores that aren't connected, then rescans; advertising cores
    /// reappear within a second or two, powered-off ones stay gone.
    public func refresh() {
        guard usesBluetooth else { return }  // preview cores can't rescan into existence
        let live = Set(links.compactMap { $0.value.link != nil ? $0.key : nil })
        discovered.removeAll { !live.contains($0.id) }
        peripherals = peripherals.filter { live.contains($0.key) }
        meters = meters.filter { live.contains($0.key) }
        signalBars = signalBars.filter { live.contains($0.key) }
        scanIfPossible()
    }

    /// A session for `core`, which is `demoCore` or one of `discovered`. Run it for as
    /// long as the core is on screen.
    public func makeSession(for core: DiscoveredCore) -> CoreSession {
        if core == demoCore {
            return CoreSession(link: FakeCoreLink.demo())
        }
        if let previewLinkFactory {
            return CoreSession(link: previewLinkFactory(core))
        }
        guard usesBluetooth else {
            preconditionFailure("makeSession(for: \(core.name)) on a preview browser without a link factory")
        }
        let central = liveCentral
        links = links.filter { $0.value.link != nil }
        if peripherals[core.id] == nil {
            // Pruned or never seen this launch; the system usually still knows it.
            peripherals[core.id] = central.retrievePeripherals(withIdentifiers: [core.id]).first
        }
        guard let peripheral = peripherals[core.id] else {
            return CoreSession(link: FailedLink(reason: CoreLinkError("\(core.name) is no longer known; go back and rescan")))
        }
        // A dying session's link may still exist for this peripheral (e.g.
        // re-entering the same core); hand over cleanly before rerouting.
        links[core.id]?.link?.superseded()
        let link = BLECoreLink(central: central, peripheral: peripheral)
        links[core.id] = WeakLink(link: link)
        return CoreSession(link: link)
    }

    private var liveCentral: CBCentralManager {
        if let central { return central }
        let created = CBCentralManager(delegate: self, queue: nil)
        central = created
        return created
    }

    private func scanIfPossible() {
        guard wantsScan, let central, central.state == .poweredOn else { return }
        // Duplicates keep RSSI updates coming for cores that are already listed.
        central.scanForPeripherals(withServices: [shinerServiceUUID],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
}

extension CoreBrowser: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isBluetoothAvailable = central.state == .poweredOn
        log.info("Bluetooth state: \(String(describing: central.state.rawValue))")
        scanIfPossible()
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        peripherals[peripheral.identifier] = peripheral
        let core = DiscoveredCore(id: peripheral.identifier, name: peripheral.name ?? "Unknown")
        if let index = discovered.firstIndex(where: { $0.id == core.id }) {
            if discovered[index] != core { discovered[index] = core }
        } else {
            log.info("Discovered \(core.name, privacy: .public)")
            discovered.append(core)
        }
        updateSignal(of: core.id, rssi: RSSI.intValue)
    }

    private func updateSignal(of id: UUID, rssi: Int) {
        if meters[id] == nil {
            meters[id] = SignalMeter(rssi: rssi)
        } else {
            meters[id]?.add(rssi: rssi)
        }
        if let bars = meters[id]?.bars, signalBars[id] != bars { signalBars[id] = bars }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        links[peripheral.identifier]?.link?.centralDidConnect()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        links[peripheral.identifier]?.link?.centralDidDisconnect(error: error)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        links[peripheral.identifier]?.link?.centralDidFailToConnect(error: error)
    }
}
