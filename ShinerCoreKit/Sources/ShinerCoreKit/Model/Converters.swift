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

    /// Decodes the property's JSON. Throws a `DecodingError`; its `summary` names the failing key.
    public init(json: String) throws {
        self = try JSONDecoder().decode(Documentation.self, from: Data(json.utf8))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blendModes = try c.decodeIfPresent([String].self, forKey: .blendModes) ?? []
        animations = try c.decodeIfPresent([String].self, forKey: .animations) ?? []
        ledColorOrders = try c.decodeIfPresent([String].self, forKey: .ledColorOrders) ?? []
    }
}

public struct DocumentationConverter: PropertyConverter {
    /// Nil for a value that fails to decode; `CoreSession` reports why.
    public static func convert(_ raw: String) -> Documentation? { try? Documentation(json: raw) }
    public static func unconvert(_ value: Documentation) -> String {
        preconditionFailure("documentation is read-only")
    }
}

extension DecodingError {
    /// The failing key path and what was wrong there, e.g.
    /// "animations: Expected to decode Array<String> but found number instead."
    public var summary: String {
        let context: Context
        switch self {
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .keyNotFound(_, let c), .dataCorrupted(let c):
            context = c
        @unknown default:
            return String(describing: self)
        }
        let path = context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
    }
}
