import CoreBluetooth

let shinerServiceUUID = CBUUID(string: "6c0de004-629d-4717-bed5-847fddfbdc2e")
let characteristicUUIDs = [
    "color":      CBUUID(string: "c116fce1-9a8a-4084-80a3-b83be2fbd108"),
    "color2":     CBUUID(string: "83595a76-1b17-4158-bcee-e702c3165caf"),
    "mode":       CBUUID(string: "70d4cabe-82cc-470a-a572-95c23f1316ff"),
    "brightness": CBUUID(string: "2B01"),
    "tau":        CBUUID(string: "d879c81a-09f0-4a24-a66c-cebf358bb97a"),
    "phi":        CBUUID(string: "df6f0905-09bd-4bf6-b6f5-45b5a4d20d52"),
    "name":       CBUUID(string: "7ad50f2a-01b5-4522-9792-d3fd4af5942f")
]

class ShinerCore : NSObject, Identifiable, CBPeripheralDelegate, ObservableObject
{
    @objc @Published var color: String?
    @objc @Published var color2: String?
    @objc @Published var mode: String?
    @objc @Published var brightness: String?
    @objc @Published var tau: String?
    @objc @Published var phi: String?
    @objc @Published var name: String?
        
    let device: CBPeripheral
    public init(for device: CBPeripheral)
    {
        self.device = device
        super.init()
        device.delegate = self
    }
    
    public func read()
    {
        print("Discovering services...")
        device.discoverServices([shinerServiceUUID])
    }
    
    public var id: UUID { device.identifier }
    public var localName: String { device.name ?? "Unknown" }
    
    
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
        
        print("Reading characteristics...")
        
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
        
        let uuid = characteristic.uuid
        guard let name = characteristicUUIDs.first(where: {$0.value == uuid})?.key
        else { return }
        
        
        print("Read characteristic \(name) as \(str).")

        DispatchQueue.main.async { [weak self] in         
            self?.setValue(str, forKey: name)
        }
    }
}

class CoreManager: NSObject, ObservableObject, CBCentralManagerDelegate
{
    var centralManager: CBCentralManager!
    var foundCore: ((ShinerCore) -> Void)!
    var lostCore: ((ShinerCore) -> Void)!
    var connectedCore: ((ShinerCore) -> Void)!
    
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
    
    func connect(to core: ShinerCore)
    {
        print("Connecting to core \(core.name)")
        centralManager.connect(core.device)
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
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    {
        let core = cores.first(where: {$0.device == peripheral})!
        print("Connected to core \(core.name)")
        connectedCore(core)
        core.read()
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect: CBPeripheral, error: Error?)
    {
        // TODO: propagate to UI
        print("Failed to connect peripheral: \(error)")
    }
  }