import Foundation

/// Identifies a firmware characteristic. String-backed so the model layer
/// has no CoreBluetooth dependency; uppercased to match CBUUID.uuidString.
public struct PropertyID: Hashable, Sendable, CustomStringConvertible {
    public let uuidString: String
    public init(_ uuidString: String) { self.uuidString = uuidString.uppercased() }
    public var description: String { uuidString }
}

/// A typed key for one core property: identity plus its wire format.
public struct PropertyKey<Converter: PropertyConverter>: Sendable {
    public let id: PropertyID
    public let name: String
    public init(_ name: String, _ uuid: String) {
        self.name = name
        self.id = PropertyID(uuid)
    }
}

/// All properties the firmware exposes. UUIDs are the spec: they must match
/// https://github.com/nevyn/shinercore.
public enum CoreProps {
    public static let color = PropertyKey<ColorConverter>("color", "c116fce1-9a8a-4084-80a3-b83be2fbd108")
    public static let color2 = PropertyKey<ColorConverter>("color2", "83595a76-1b17-4158-bcee-e702c3165caf")
    public static let speed = PropertyKey<DoubleConverter>("speed", "5341966c-da42-4b65-9c27-5de57b642e28")
    public static let mode = PropertyKey<IntConverter>("mode", "70d4cabe-82cc-470a-a572-95c23f1316ff")
    public static let brightness = PropertyKey<IntConverter>("brightness", "2B01")
    public static let tau = PropertyKey<DoubleConverter>("tau", "d879c81a-09f0-4a24-a66c-cebf358bb97a")
    public static let phi = PropertyKey<DoubleConverter>("phi", "df6f0905-09bd-4bf6-b6f5-45b5a4d20d52")
    public static let name = PropertyKey<StringConverter>("name", "7ad50f2a-01b5-4522-9792-d3fd4af5942f")
    public static let layer = PropertyKey<IntConverter>("layer", "0a7eadd8-e4b8-4384-8308-e67a32262cc4")
    public static let preset = PropertyKey<IntConverter>("preset", "8b989f5e-3d22-4377-80c9-c54eeb459518")
    public static let animation = PropertyKey<StringConverter>("animation", "bee29c30-aa11-45b2-b5a2-8ff8d0bab262")
    public static let beatSync = PropertyKey<IntConverter>("beatSync", "6f97efc2-096e-4704-9feb-f9c2f41577ee")
    public static let blendMode = PropertyKey<StringConverter>("blendMode", "03686c5c-6e6f-44f0-943f-db6388d9fdd4")
    public static let ledOrder = PropertyKey<StringConverter>("ledOrder", "f3b7c8a1-5d2e-4f19-8c6a-9e1d0b2c3a4f")
    public static let ledCount = PropertyKey<IntConverter>("ledCount", "f5c67dcb-8798-4818-901f-cff9917d1a62")
    public static let mic = PropertyKey<IntConverter>("mic", "519f61ae-bb92-425f-90fa-29aabc63520d")
    public static let documentation = PropertyKey<DocumentationConverter>("documentation", "76db9199-21af-4207-a23c-dc138a6cd42d")
}
