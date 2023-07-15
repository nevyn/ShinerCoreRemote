import CoreBluetooth

let shinerServiceUUID = CBUUID(string: "6c0de004-629d-4717-bed5-847fddfbdc2e")
let colorCharacteristicUUID = CBUUID(string: "c116fce1-9a8a-4084-80a3-b83be2fbd108")

class ShinerCore : NSObject, Identifiable, CBPeripheralDelegate
{
    @Published var color: String?
        
    let device: CBPeripheral
    init(for device: CBPeripheral)
    {
        self.device = device
        super.init()
        device.delegate = self
        print("Discovering services...")
        device.discoverServices([shinerServiceUUID])
    }
    
    public var id: UUID { device.identifier }
    
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    {
        guard let services = peripheral.services else
        {
            print("lol no services")
            return
        }
        
        guard let shinerService = services.first(where: { $0.uuid == shinerServiceUUID }) else
        {
            print("lol no shiner service")
            return
        }
        
        print("Discovering characteristics...")
        device.discoverCharacteristics(nil, for: shinerService)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    {
        guard let chars = service.characteristics else
        {
            print("lol no characteristics")
            return
        }
        
        for char in chars
        {
            device.readValue(for: char)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    {
        guard 
            let data = characteristic.value, 
            let str = String(data: data, encoding: .utf8)
        else
        {
            print("lol unreadable characteristic")
            return
        }
        
        if characteristic.uuid == colorCharacteristicUUID
        {
            self.color = str
        }
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