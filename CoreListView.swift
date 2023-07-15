import SwiftUI
import CoreBluetooth

class BLEScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    var centralManager: CBCentralManager!
    var peripheralDiscoveredHandler: ((CBPeripheral) -> Void)?
    var peripheralDisappearedHandler: ((CBPeripheral) -> Void)?
    
    private var discoveredPeripherals: [CBPeripheral] = []
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func scanForBLEAccessories() {
        centralManager.scanForPeripherals(withServices: [CBUUID(string: "6c0de004-629d-4717-bed5-847fddfbdc2e")], options: nil)
    }
    
    // CBCentralManagerDelegate methods
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            scanForBLEAccessories()
        } else {
            print("Bluetooth is not available.")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredPeripherals.contains(peripheral) {
            discoveredPeripherals.append(peripheral)
            peripheralDiscoveredHandler?(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let index = discoveredPeripherals.firstIndex(of: peripheral) {
            discoveredPeripherals.remove(at: index)
            peripheralDisappearedHandler?(peripheral)
        }
    }
}

struct CoreListView : View {
    @StateObject private var bleScanner = BLEScanner()
    @State private var peripherals: [CBPeripheral] = []
    @State private var connectedPeripheral: CBPeripheral?
    
    var body: some View {
        NavigationView {
            VStack {
                List(peripherals, id: \.self) { peripheral in
                    NavigationLink(
                        destination: CoreControlsView(peripheral: peripheral),
                        tag: peripheral,
                        selection: $connectedPeripheral
                    ) {
                        Text(peripheral.name ?? "Unknown")
                    }
                    .onTapGesture {
                        connect(to: peripheral)
                    }
                }
            }
            .navigationTitle("Nearby cores ✨")
        }
        .onAppear {
            bleScanner.peripheralDiscoveredHandler = { peripheral in
                peripherals.append(peripheral)
            }
            
            bleScanner.peripheralDisappearedHandler = { peripheral in
                peripherals.removeAll { $0 == peripheral }
            }
        }
    }
    
    private func connect(to peripheral: CBPeripheral) {
        bleScanner.centralManager.connect(peripheral, options: nil)
        connectedPeripheral = peripheral
    }
}

extension CBPeripheral: Identifiable {
    public var id: UUID { identifier }
}
