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
    public private(set) var discovered: [DiscoveredCore] = []
    public private(set) var isBluetoothAvailable = false

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var links: [UUID: WeakLink] = [:]
    @ObservationIgnored private var wantsScan = false
    @ObservationIgnored private var previewLinkFactory: ((DiscoveredCore) -> any CoreLink)?
    @ObservationIgnored private let log = Logger(subsystem: "jpg.nevyn.shinerconf", category: "browser")

    private struct WeakLink { weak var link: BLECoreLink? }

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// Preview/demo-only: canned cores and no Bluetooth; sessions come from
    /// `linkFactory` (typically `{ _ in FakeCoreLink.demo() }`).
    public init(previewCores: [DiscoveredCore], linkFactory: ((DiscoveredCore) -> any CoreLink)? = nil) {
        discovered = previewCores
        isBluetoothAvailable = true
        previewLinkFactory = linkFactory
        super.init()
    }

    public func startScanning() {
        wantsScan = true
        scanIfPossible()
    }

    public func stopScanning() {
        wantsScan = false
        central?.stopScan()
    }

    /// Forgets cores that aren't connected, then rescans; advertising cores
    /// reappear within a second or two, powered-off ones stay gone.
    public func refresh() {
        guard central != nil else { return }  // preview cores can't rescan into existence
        let live = Set(links.compactMap { $0.value.link != nil ? $0.key : nil })
        discovered.removeAll { !live.contains($0.id) }
        peripherals = peripherals.filter { live.contains($0.key) }
        scanIfPossible()
    }

    public func makeSession(for core: DiscoveredCore) -> CoreSession {
        if let previewLinkFactory {
            return CoreSession(link: previewLinkFactory(core))
        }
        guard let central, let peripheral = peripherals[core.id] else {
            preconditionFailure("makeSession for unknown core \(core.id)")
        }
        let link = BLECoreLink(central: central, peripheral: peripheral)
        links[core.id] = WeakLink(link: link)
        return CoreSession(link: link)
    }

    private func scanIfPossible() {
        guard wantsScan, let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [shinerServiceUUID])
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
