import CoreBluetooth
import SwiftUI

let shinerServiceUUID = CBUUID(string: "6c0de004-629d-4717-bed5-847fddfbdc2e")

class CorePropertyBase : ObservableObject
{
    let name: String
    @objc let uuid: CBUUID
    @Published @objc var rawValue: String? = nil
    let throttler = Throttler(duration: 0.1)
    
    fileprivate var characteristic: CBCharacteristic! = nil    
    
    init(name: String, uuid: CBUUID)
    {
        self.name = name
        self.uuid = uuid
    }
}
class CoreProperty<ConverterType> : CorePropertyBase
where ConverterType : PropertyConverter
{
    let converter = ConverterType.init()
    func convertedValue() -> ConverterType.ValueType?
    {
        return converter.convert(rawValue)
    }
    func unconvertedValue(value: ConverterType.ValueType) -> String
    {
        return converter.unconvert(value)
    }
}

class ShinerCore : NSObject, Identifiable, CBPeripheralDelegate, ObservableObject
{
    let color = CoreProperty<ColorConverter>(name: "color", uuid: CBUUID(string: "c116fce1-9a8a-4084-80a3-b83be2fbd108"))
    let color2 = CoreProperty<ColorConverter>(name: "color2", uuid: CBUUID(string: "83595a76-1b17-4158-bcee-e702c3165caf"))
    let speed = CoreProperty<DoubleConverter>(name: "speed", uuid: CBUUID(string: "5341966c-da42-4b65-9c27-5de57b642e28"))
    let mode = CoreProperty<IntConverter>(name: "mode", uuid: CBUUID(string: "70d4cabe-82cc-470a-a572-95c23f1316ff"))
    let brightness = CoreProperty<IntConverter>(name: "brightness", uuid: CBUUID(string: "2B01"))
    let tau = CoreProperty<DoubleConverter>(name: "tau", uuid: CBUUID(string: "d879c81a-09f0-4a24-a66c-cebf358bb97a"))
    let phi = CoreProperty<DoubleConverter>(name: "phi", uuid: CBUUID(string: "df6f0905-09bd-4bf6-b6f5-45b5a4d20d52"))
    let name = CoreProperty<StringConverter>(name: "name", uuid: CBUUID(string: "7ad50f2a-01b5-4522-9792-d3fd4af5942f"))
    let layer = CoreProperty<IntConverter>(name: "layer", uuid: CBUUID(string: "0a7eadd8-e4b8-4384-8308-e67a32262cc4"))
    let animation = CoreProperty<IntConverter>(name: "animation", uuid: CBUUID(string: "bee29c30-aa11-45b2-b5a2-8ff8d0bab262"))
    var properties: [String: CorePropertyBase] = [:]
    
    let device: CBPeripheral
    public init(for device: CBPeripheral)
    {
        self.device = device
        super.init()
        device.delegate = self
        for prop in [color, color2, speed, mode, brightness, tau, phi, name, layer, animation] {
            properties[prop.uuid.uuidString] = prop
        }
    }
    
    public func read()
    {
        print("Discovering services...")
        device.discoverServices([shinerServiceUUID])
    }
    
    public func write(newValue: String, to prop: CorePropertyBase)
    {
        self.objectWillChange.send()
        prop.rawValue = newValue
        prop.throttler.submit { [weak self] in
            guard let self = self else { return }
            guard let data = prop.rawValue?.data(using: .utf8, allowLossyConversion: false) else { return }
            print("Writing prop \(prop.name) = \(prop.rawValue!)")
            device.writeValue(data, for: prop.characteristic, type: .withResponse)

        }
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
            let uuid = char.uuid
            guard let prop = properties[uuid.uuidString]
            else { continue }
            prop.characteristic = char
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
        guard let prop = properties[uuid.uuidString]
        else { return }
        
        print("Read characteristic \(prop.name) as \(str).")

        self.objectWillChange.send()
        prop.rawValue = str
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            // todo: propagate to UI
            print("Failed to write characteristic: \(String(describing: error))")
            return
        }
    }
}

class CoreManager: NSObject, ObservableObject, CBCentralManagerDelegate
{
    var centralManager: CBCentralManager!
    var foundCore: ((ShinerCore) -> Void)!
    var lostCore: ((ShinerCore) -> Void)!
    var connectedCore: ((ShinerCore) -> Void)!
    var disconnectedCore: ((ShinerCore) -> Void)!
    
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
        print("Connecting to core \(core.localName)")
        centralManager.connect(core.device)
    }
    
    func disconnect(from core: ShinerCore)
    {
        centralManager.cancelPeripheralConnection(core.device)
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
        print("Connected to core \(core.localName)")
        connectedCore(core)
        core.read()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let core = cores.first(where: {$0.device == peripheral}) else { return }
        print("Disconnected from core \(core.localName)")
        disconnectedCore(core)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect: CBPeripheral, error: Error?)
    {
        // TODO: propagate to UI
        print("Failed to connect peripheral: \(String(describing: error))")
    }
}

protocol PropertyConverter {
    associatedtype ValueType
    init()
    func convert(_ string: String?) -> ValueType?
    func unconvert(_ value: ValueType) -> String
}

struct DoubleConverter: PropertyConverter {
    typealias ValueType = Double
    init() {}
    func convert(_ string: String?) -> Double? {
        guard let string = string else { return nil }
        return Double(string)
    }
    func unconvert(_ value: Double) -> String {
        return String(value)
    }
}
struct StringConverter: PropertyConverter {
    typealias ValueType = String
    init() {}
    func convert(_ string: String?) -> String? {
        return string
    }
    func unconvert(_ value: String) -> String {
        return value
    }
}

struct IntConverter: PropertyConverter {
    typealias ValueType = Int
    init() {}
    func convert(_ string: String?) -> Int? {
        guard let string = string else { return nil }
        return Int(string)
    }
    
    func unconvert(_ value: Int) -> String {
        return String(value)
    }
}

struct ColorConverter: PropertyConverter {
    typealias ValueType = Color
    init() {}
    func convert(_ string: String?) -> Color? {
        guard let rawValue = string else {
            return nil
        }
        
        let components = rawValue.components(separatedBy: " ")
        guard components.count == 3,
              let red = Double(components[0]),
              let green = Double(components[1]),
              let blue = Double(components[2]),
              red >= 0, red <= 255,
              green >= 0, green <= 255,
              blue >= 0, blue <= 255 else {
            return nil
        }
        
        let color = Color(red: red / 255, green: green / 255, blue: blue / 255)
        return color
    }
    
    func unconvert(_ value: Color) -> String {
        let (red, green, blue, _) = value.rgba
        return "\(Int(red*255)) \(Int(green*255)) \(Int(blue*255))"
    }
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    #if canImport(UIKit)
    var asNative: UIColor { UIColor(self) }
    #elseif canImport(AppKit)
    var asNative: NSColor { NSColor(self) }
    #endif

    var rgba: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let color = asNative //.usingColorSpace(.deviceRGB)!
        var t = (CGFloat(), CGFloat(), CGFloat(), CGFloat())
        color.getRed(&t.0, green: &t.1, blue: &t.2, alpha: &t.3)
        return t
    }

    var hsva: (hue: CGFloat, saturation: CGFloat, value: CGFloat, alpha: CGFloat) {
        let color = asNative //.usingColorSpace(.deviceRGB)!
        var t = (CGFloat(), CGFloat(), CGFloat(), CGFloat())
        color.getHue(&t.0, saturation: &t.1, brightness: &t.2, alpha: &t.3)
        return t
    }
}

class Throttler
{
    private let duration: TimeInterval
    private var task: Task<Void, Error>?
    
    init(duration: TimeInterval)
    {
        self.duration = duration
    }
    
    func submit(operation: @escaping () async -> Void)
    {
        guard task == nil else { return }
        
        task = Task {
            try? await sleep()
            await operation()
            task = nil
        }
    }
    
    func sleep() async throws
    {
        try await Task.sleep(nanoseconds: UInt64(duration * TimeInterval(NSEC_PER_SEC)))
    }
}
