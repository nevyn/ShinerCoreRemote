import Foundation

/// Translates between a property's wire format (UTF-8 string) and its Swift value.
public protocol PropertyConverter: Sendable {
    associatedtype ValueType
    static func convert(_ raw: String) -> ValueType?
    static func unconvert(_ value: ValueType) -> String
}

public struct StringConverter: PropertyConverter {
    public static func convert(_ raw: String) -> String? { raw }
    public static func unconvert(_ value: String) -> String { value }
}

public struct IntConverter: PropertyConverter {
    public static func convert(_ raw: String) -> Int? { Int(raw) }
    public static func unconvert(_ value: Int) -> String { String(value) }
}

public struct DoubleConverter: PropertyConverter {
    public static func convert(_ raw: String) -> Double? { Double(raw) }
    public static func unconvert(_ value: Double) -> String { String(value) }
}

/// The `documentation` property: firmware-provided value vocabularies.
public struct Documentation: Equatable, Sendable, Decodable {
    public let blendModes: [String]
    public let animations: [String]
    public let ledColorOrders: [String]

    public init(blendModes: [String] = [], animations: [String] = [], ledColorOrders: [String] = []) {
        self.blendModes = blendModes
        self.animations = animations
        self.ledColorOrders = ledColorOrders
    }

    private enum CodingKeys: String, CodingKey {
        case blendModes, animations, ledColorOrders
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blendModes = try c.decodeIfPresent([String].self, forKey: .blendModes) ?? []
        animations = try c.decodeIfPresent([String].self, forKey: .animations) ?? []
        ledColorOrders = try c.decodeIfPresent([String].self, forKey: .ledColorOrders) ?? []
    }
}

public struct DocumentationConverter: PropertyConverter {
    public static func convert(_ raw: String) -> Documentation? {
        try? JSONDecoder().decode(Documentation.self, from: Data(raw.utf8))
    }
    public static func unconvert(_ value: Documentation) -> String {
        preconditionFailure("documentation is read-only")
    }
}
