import CoreBluetooth

class ShinerCore : Identifiable, Hashable, Equatable
{
    let device: CBPeripheral
    init(for device: CBPeripheral)
    {
        self.device = device
    }
    
    public var id: UUID { device.identifier }
    
    func hash(into hasher: inout Hasher)
    {
        device.hash(into: &hasher)
    }
    
    static func == (lhs: ShinerCore, rhs: ShinerCore) -> Bool
    {
        return lhs.device == rhs.device
    }
}

class CoreManager: NSObject, ObservableObject, CBCentralManagerDelegate
{
    var centralManager: CBCentralManager!
    var foundCore: ((ShinerCore) -> Void)!
    var lostCore: ((ShinerCore) -> Void)!
    
    private var cores: [ShinerCore] = []
    
    override init()
    {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func scanForBLEAccessories()
    {
        centralManager.scanForPeripherals(withServices: [CBUUID(string: "6c0de004-629d-4717-bed5-847fddfbdc2e")], options: nil)
    }
    
    // CBCentralManagerDelegate methods
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    {
        if central.state == .poweredOn
        {
            scanForBLEAccessories()
        }
        else
        {
            print("Bluetooth is not available.")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber)
    {
        if !cores.contains(where: {$0.device == peripheral}) {
            let newCore = ShinerCore(for: peripheral)
            cores.append(newCore)
            foundCore(newCore)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
    {
        if let coreIndex = cores.firstIndex(where: {$0.device == peripheral})
        {
            let core = cores[coreIndex]
            cores.remove(at: coreIndex)
            lostCore(core)
        }
    }
  }