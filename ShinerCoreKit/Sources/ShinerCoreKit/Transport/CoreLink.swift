import Foundation

public struct CoreLinkError: Error, CustomStringConvertible, Equatable, Sendable {
    public let description: String
    public init(_ description: String) { self.description = description }
    public init(wrapping error: some Error) {
        self.description = (error as NSError).localizedDescription
    }
}

public enum CoreLinkEvent: Sendable, Equatable {
    /// Ready to talk properties (services and characteristics discovered).
    case connected
    /// Link lost; nil reason means intentional/clean.
    case disconnected(reason: CoreLinkError?)
    /// The firmware exposes this property.
    case becameAvailable(PropertyID)
    case valueRead(PropertyID, String)
    case readFailed(PropertyID, CoreLinkError)
}

/// The seam between the session and a device. `BLECoreLink` is the real one;
/// `FakeCoreLink` is the same contract scripted for previews and tests.
@MainActor
public protocol CoreLink: AnyObject {
    /// Single-consumer, buffers until consumed, lives as long as the link.
    var events: AsyncStream<CoreLinkEvent> { get }
    /// Standing intent: keeps trying until it succeeds or `disconnect()` is called.
    func connect()
    func disconnect()
    /// Completes when the device acks the write.
    func write(_ raw: String, to id: PropertyID) async throws
    /// Requests a fresh read of every available property; results arrive as `valueRead` events.
    func readAll()
}
