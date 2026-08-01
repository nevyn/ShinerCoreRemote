import CoreBluetooth
import os

@MainActor let shinerServiceUUID = CBUUID(string: "6c0de004-629d-4717-bed5-847fddfbdc2e")

/// `CoreLink` over a CBPeripheral. Central-level callbacks (connect,
/// disconnect) are forwarded in by `CoreBrowser`, which owns the central.
/// Peripheral-level callbacks arrive here directly, on the main queue.
@MainActor
final class BLECoreLink: NSObject, CoreLink {
    nonisolated let events: AsyncStream<CoreLinkEvent>
    private let emit: AsyncStream<CoreLinkEvent>.Continuation
    private let central: CBCentralManager
    private let peripheral: CBPeripheral
    private var characteristics: [PropertyID: CBCharacteristic] = [:]
    private var writeWaiters: [PropertyID: [CheckedContinuation<Void, any Error>]] = [:]
    private let log = Logger(subsystem: "jpg.nevyn.shinerconf", category: "ble")

    init(central: CBCentralManager, peripheral: CBPeripheral) {
        self.central = central
        self.peripheral = peripheral
        (events, emit) = AsyncStream.makeStream()
        super.init()
        peripheral.delegate = self
    }

    func connect() {
        log.info("Connecting to \(self.peripheral.name ?? "?", privacy: .public)")
        central.connect(peripheral)
    }

    func disconnect() {
        // A newer link for this peripheral has taken over (it repointed the
        // delegate); tearing down the shared connection would sabotage it.
        guard peripheral.delegate === self else { return }
        log.info("Disconnecting from \(self.peripheral.name ?? "?", privacy: .public)")
        central.cancelPeripheralConnection(peripheral)
    }

    /// Called by CoreBrowser when a newer link replaces this one: fail
    /// in-flight writes and tell the (dying) session it's over, without
    /// touching the shared connection the successor is about to use.
    func superseded() {
        linkDropped(reason: nil)
    }

    func write(_ raw: String, to id: PropertyID) async throws {
        guard let characteristic = characteristics[id] else {
            throw CoreLinkError("Property \(id) is not available on this core")
        }
        try await withCheckedThrowingContinuation { continuation in
            writeWaiters[id, default: []].append(continuation)
            peripheral.writeValue(Data(raw.utf8), for: characteristic, type: .withResponse)
        }
    }

    func read(_ id: PropertyID) {
        guard let characteristic = characteristics[id] else {
            emit.yield(.readFailed(id, CoreLinkError("Property \(id) is not available on this core")))
            return
        }
        peripheral.readValue(for: characteristic)
    }

    // Forwarded by CoreBrowser from the central's delegate.

    func centralDidConnect() {
        log.info("Connected; discovering services")
        peripheral.discoverServices([shinerServiceUUID])
    }

    func centralDidDisconnect(error: (any Error)?) {
        linkDropped(reason: error.map { CoreLinkError(wrapping: $0) })
    }

    func centralDidFailToConnect(error: (any Error)?) {
        linkDropped(reason: error.map { CoreLinkError(wrapping: $0) } ?? CoreLinkError("Failed to connect"))
    }

    private func linkDropped(reason: CoreLinkError?) {
        characteristics = [:]  // stale after disconnect; rediscovered on reconnect
        let waiters = writeWaiters.values.flatMap(\.self)
        writeWaiters = [:]
        for waiter in waiters {
            waiter.resume(throwing: reason ?? CoreLinkError("Disconnected"))
        }
        emit.yield(.disconnected(reason: reason))
    }
}

extension BLECoreLink: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == shinerServiceUUID }) else {
            // Not a transient failure: reconnecting to this device is pointless.
            emit.yield(.incompatible(CoreLinkError("Device has no ShinerCore service")))
            central.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        if let error {
            // Transient GATT failure: drop and let the session retry.
            linkDropped(reason: CoreLinkError(wrapping: error))
            central.cancelPeripheralConnection(peripheral)
            return
        }
        for characteristic in service.characteristics ?? [] {
            let id = PropertyID(characteristic.uuid.uuidString)
            characteristics[id] = characteristic
            emit.yield(.becameAvailable(id))
        }
        emit.yield(.connected)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        let id = PropertyID(characteristic.uuid.uuidString)
        if let error {
            emit.yield(.readFailed(id, CoreLinkError(wrapping: error)))
        } else if let data = characteristic.value, let raw = String(data: data, encoding: .utf8) {
            emit.yield(.valueRead(id, raw))
        } else {
            emit.yield(.readFailed(id, CoreLinkError("Value is not UTF-8")))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        let id = PropertyID(characteristic.uuid.uuidString)
        guard var waiters = writeWaiters[id], !waiters.isEmpty else { return }
        let continuation = waiters.removeFirst()
        writeWaiters[id] = waiters
        if let error {
            continuation.resume(throwing: CoreLinkError(wrapping: error))
        } else {
            continuation.resume()
        }
    }
}
