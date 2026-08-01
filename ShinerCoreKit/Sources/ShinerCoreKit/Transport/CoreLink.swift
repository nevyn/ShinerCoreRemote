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
    /// This device will never work (e.g. lacks the ShinerCore service);
    /// unlike `disconnected`, reconnecting is pointless.
    case incompatible(CoreLinkError)
    /// The firmware exposes this property.
    case becameAvailable(PropertyID)
    /// Response to a `read(_:)` request — exactly one per request.
    case valueRead(PropertyID, String)
    case readFailed(PropertyID, CoreLinkError)
    /// Unsolicited device-side change (a notification): another central
    /// wrote it, the layer/preset cursor fanned out, or our own write echoed.
    case valueChanged(PropertyID, String)
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
    /// Requests a fresh read; the result arrives as a `valueRead` or
    /// `readFailed` event — exactly one per request, which is what lets the
    /// session count outstanding reads for staleness tracking.
    func read(_ id: PropertyID)
}

/// A link for a core that can no longer be reached at all (e.g. the system
/// forgot the peripheral). Reports `incompatible` so the UI shows why.
@MainActor
final class FailedLink: CoreLink {
    let events: AsyncStream<CoreLinkEvent>
    private let emit: AsyncStream<CoreLinkEvent>.Continuation
    private let reason: CoreLinkError

    init(reason: CoreLinkError) {
        self.reason = reason
        (events, emit) = AsyncStream.makeStream()
    }

    func connect() { emit.yield(.incompatible(reason)) }
    func disconnect() {}
    func write(_ raw: String, to id: PropertyID) async throws { throw reason }
    func read(_ id: PropertyID) {}
}
