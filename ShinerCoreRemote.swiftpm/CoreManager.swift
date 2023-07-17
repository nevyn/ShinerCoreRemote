import CoreBluetooth
import SwiftUI

let shinerServiceUUID = CBUUID(string: "6c0de004-629d-4717-bed5-847fddfbdc2e")

struct CoreProperty<T>
{
    let name: String
    let uuid: CBUUID
    var rawValue: String? = nil
    let converter: PropertyConverter<T>
    
    func convertedValue() -> T?
    {
        return converter.convert(rawValue)
    }
    func unconvertedValue(value: T) -> String?
    {
        return converter.unconvert(value)
    }
}

class ShinerCore : NSObject, Identifiable, CBPeripheralDelegate, ObservableObject
{
    var properties = [
        "color": CoreProperty.create(name: "color", uuid: CBUUID(string: "c116fce1-9a8a-4084-80a3-b83be2fbd108"), converter: PropertyConverter.color()),
        "color2": CoreProperty.create(name: "color2", uuid: CBUUID(string: "83595a76-1b17-4158-bcee-e702c3165caf"), converter: PropertyConverter.color()),
        "mode": CoreProperty.create(name: "mode", uuid: CBUUID(string: "70d4cabe-82cc-470a-a572-95c23f1316ff"), converter: PropertyConverter.int()),
        "brightness": CoreProperty(name: "brightness", uuid: CBUUID(string: "2B01"), converter: PropertyConverter.color()),
        "tau": CoreProperty.create(name: "tau", uuid: CBUUID(string: "d879c81a-09f0-4a24-a66c-cebf358bb97a"), converter: PropertyConverter.number()),
        "phi": CoreProperty.create(name: "phi", uuid: CBUUID(string: "df6f0905-09bd-4bf6-b6f5-45b5a4d20d52"), converter: PropertyConverter.number()),
        "name": CoreProperty.create(name: "name", uuid: CBUUID(string: "7ad50f2a-01b5-4522-9792-d3fd4af5942f"), converter: PropertyConverter.string())
    ]
        
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
        guard let prop = properties.values.first(where: {$0.uuid == uuid})
        else { return }
        
        
        print("Read characteristic \(prop.name) as \(str).")

        DispatchQueue.main.async { [weak self] in
            prop.rawValue = str
            objectWillChange.send()
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
        print("Failed to connect peripheral: \(error)")
    }
}

struct PropertyConverter<T>
{
    let convert: (String?) -> T?
    let unconvert: (T) -> String?
    
    static func string() -> PropertyConverter<String> {
        PropertyConverter<String>(
            convert: { $0 },
            unconvert: { $0 }
        )
    }
    
    static func int() -> PropertyConverter<Int> {
        PropertyConverter<Int>(
            convert: { Int($0 ?? "") },
            unconvert: { String($0) }
        )
    }
    
    static func number() -> PropertyConverter<Double> {
        PropertyConverter<Double>(
            convert: { Double($0 ?? "") },
            unconvert: { String($0) }
        )
    }
    
    static func color() -> PropertyConverter<Color> {
        PropertyConverter<Color>(
            convert: { rawValue in
                guard let rawValue = rawValue else {
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
            },
            unconvert: { color in
                let (red, green, blue, _) = color.rgba
                return "\(Int(red*255)) \(Int(green*255)) \(Int(blue*255))"
            }
        )
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
