import Foundation

/// How one animation uses a layer's settings: one entry of the `animationDocs` property,
/// or of the render library's animation table.
public struct AnimationDoc: Equatable, Sendable {
    /// How many of `color` and `color2` the animation reads: 0 (it makes its own),
    /// 1 (`color` only) or 2.
    public let colors: Int
    /// What the animation calls tau and phi ("Tail length"); nil when it ignores one.
    public let tau: String?
    public let phi: String?

    public init(colors: Int, tau: String?, phi: String?) {
        self.colors = colors
        self.tau = tau
        self.phi = phi
    }

    /// For an animation that neither the core nor the render library documents.
    public static let generic = AnimationDoc(colors: 2, tau: "Tau", phi: "Phi")
}

extension AnimationDoc: Decodable {
    /// Wire format: `[colors]`, `[colors, "tau name"]` or `[colors, "tau name", "phi name"]`,
    /// where `""` names an ignored parameter. Later elements are ignored.
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let colors = try c.decode(Int.self)
        guard (0 ... 2).contains(colors) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "colors must be 0, 1 or 2, not \(colors)"))
        }
        let tau = c.isAtEnd ? "" : try c.decode(String.self)
        let phi = c.isAtEnd ? "" : try c.decode(String.self)
        self.init(colors: colors, tau: tau.isEmpty ? nil : tau, phi: phi.isEmpty ? nil : phi)
    }
}

/// The `animationDocs` property: one `AnimationDoc` per animation, in the order of
/// `Documentation.animations`. Firmware that predates it doesn't have the property.
public struct AnimationDocs: Equatable, Sendable {
    public let entries: [AnimationDoc]

    public init(entries: [AnimationDoc]) {
        self.entries = entries
    }

    /// Decodes the property's JSON. Throws a `DecodingError`; its `summary` names the failing entry.
    public init(json: String) throws {
        entries = try JSONDecoder().decode([AnimationDoc].self, from: Data(json.utf8))
    }
}

public struct AnimationDocsConverter: PropertyConverter {
    /// Nil for a value that fails to decode; `CoreSession` reports why.
    public static func convert(_ raw: String) -> AnimationDocs? { try? AnimationDocs(json: raw) }
    public static func unconvert(_ value: AnimationDocs) -> String {
        preconditionFailure("animationDocs is read-only")
    }
}

public extension CoreState {
    /// How the named animation uses colors and what it calls tau and phi. Prefers the
    /// core's `animationDocs`, then the render library's table by name, then `.generic`.
    func animationDoc(for name: String) -> AnimationDoc {
        if let entries = animationDocs?.entries,
           let index = documentation?.animations.firstIndex(of: name),
           entries.indices.contains(index) {
            return entries[index]
        }
        return RenderLibrary.animationDoc(named: name) ?? .generic
    }
}
