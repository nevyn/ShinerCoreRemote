import CoreBluetooth
import SwiftUI

let shinerServiceUUID = CBUUID(string: "6c0de004-629d-4717-bed5-847fddfbdc2e")

class CorePropertyBase
{
    let name: String
    @objc let uuid: CBUUID
    @objc var rawValue: String? = nil
    
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
    func unconvertedValue(value: ConverterType.ValueType) -> String?
    {
        return converter.unconvert(value)
    }
}

class ShinerCore : NSObject, Identifiable, CBPeripheralDelegate, ObservableObject
{
    let color = CoreProperty<ColorConverter>(name: "color", uuid: CBUUID(string: "c116fce1-9a8a-4084-80a3-b83be2fbd108"))
    let color2 = CoreProperty<ColorConverter>(name: "color2", uuid: CBUUID(string: "83595a76-1b17-4158-bcee-e702c3165caf"))
    let mode = CoreProperty<IntConverter>(name: "mode", uuid: CBUUID(string: "70d4cabe-82cc-470a-a572-95c23f1316ff"))
    let brightness = CoreProperty<DoubleConverter>(name: "brightness", uuid: CBUUID(string: "2B01"))
    let tau = CoreProperty<DoubleConverter>(name: "tau", uuid: CBUUID(string: "d879c81a-09f0-4a24-a66c-cebf358bb97a"))
    let phi = CoreProperty<DoubleConverter>(name: "phi", uuid: CBUUID(string: "df6f0905-09bd-4bf6-b6f5-45b5a4d20d52"))
    let name = CoreProperty<StringConverter>(name: "name", uuid: CBUUID(string: "7ad50f2a-01b5-4522-9792-d3fd4af5942f"))
    var properties: [String: CorePropertyBase] = [:]
    
    let device: CBPeripheral
    public init(for device: CBPeripheral)
    {
        self.device = device
        super.init()
        device.delegate = self
        for prop in [color, color2, mode, brightness, tau, phi, name] {
            properties[prop.uuid.uuidString] = prop            
        }
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
        guard let prop = properties[uuid.uuidString]
        else { return }
        
        print("Read characteristic \(prop.name) as \(str).")

        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
            prop.rawValue = str
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
        print("Connecting to core \(core.localName)")
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
        print("Connected to core \(core.localName)")
        connectedCore(core)
        core.read()
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
