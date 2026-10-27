import Testing
import Foundation
@testable import ShinerCoreKit

/// Polls until `condition` holds or the timeout passes; the caller then
/// asserts the condition itself for a readable failure.
@MainActor
func settle(timeout: Duration = .seconds(2), until condition: () -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
struct SessionHarness {
    let fake: FakeCoreLink
    let session: CoreSession
    let runner: Task<Void, Never>

    init(fake: FakeCoreLink = .demo()) async {
        self.fake = fake
        session = CoreSession(link: fake, throttle: .milliseconds(10))
        let s = session
        runner = Task { await s.run() }
        await settle { s.connection == .connected && s.state[CoreProps.brightness] != nil }
    }

    func stop() async {
        runner.cancel()
        await settle { fake.disconnectCount > 0 }
    }
}

@Suite @MainActor struct CoreSessionTests {
    @Test func connectPopulatesState() async {
        let h = await SessionHarness()
        #expect(h.session.connection == .connected)
        #expect(h.session.state[CoreProps.brightness] == 180)
        #expect(h.session.state[CoreProps.name] == "Nevyn")
        #expect(h.session.state.isAvailable(CoreProps.tau))
        #expect(h.session.state.documentation?.animations.contains("rainbow") == true)
        await h.stop()
    }

    @Test func throttleCollapsesDragIntoOneWrite() async {
        let h = await SessionHarness()
        for value in 1...50 {
            h.session.set(CoreProps.brightness, to: value)
        }
        #expect(h.session.state[CoreProps.brightness] == 50, "optimistic update is immediate")
        await settle { h.fake.written.contains { $0.id == CoreProps.brightness.id } }
        let writes = h.fake.written.filter { $0.id == CoreProps.brightness.id }
        #expect(writes.map(\.raw) == ["50"], "one trailing-edge write with the final value")
        await h.stop()
    }

    @Test func inboundReadsAreDroppedWhileWritePending() async {
        let h = await SessionHarness()
        h.session.set(CoreProps.brightness, to: 42)
        h.fake.inject(.valueRead(CoreProps.brightness.id, "7"))  // stale refetch racing the drag
        await settle { h.fake.written.contains { $0.id == CoreProps.brightness.id } }
        #expect(h.session.state[CoreProps.brightness] == 42)

        try? await Task.sleep(for: .milliseconds(50))  // drain finishes, dirty clears
        h.fake.inject(.valueRead(CoreProps.brightness.id, "7"))
        await settle { h.session.state[CoreProps.brightness] == 7 }
        #expect(h.session.state[CoreProps.brightness] == 7, "reads apply again once clean")
        await h.stop()
    }

    @Test func equalValueWritesAreSkipped() async {
        let h = await SessionHarness()
        h.session.set(CoreProps.brightness, to: 180)  // same as device value
        try? await Task.sleep(for: .milliseconds(50))
        #expect(h.fake.written.isEmpty)
        await h.stop()
    }

    @Test func selectWritesImmediatelyAndRefetches() async {
        let h = await SessionHarness()
        h.fake.values[CoreProps.brightness.id] = "99"  // device-side fanout of a layer switch
        h.session.select(CoreProps.layer, 3)
        await settle { h.session.state[CoreProps.brightness] == 99 }
        #expect(h.fake.written.contains { $0.id == CoreProps.layer.id && $0.raw == "3" })
        #expect(h.session.state[CoreProps.brightness] == 99, "refetch after select picked up dependent props")
        await h.stop()
    }

    @Test func dropReconnectsWhileSessionLives() async {
        let h = await SessionHarness()
        h.fake.becomeUnreachable()
        await settle { h.session.connection == .reconnecting }
        #expect(h.session.connection == .reconnecting)
        #expect(h.fake.connectCount == 2, "standing reconnect intent was issued")

        h.fake.values[CoreProps.brightness.id] = "11"
        h.fake.becomeReachable()
        await settle { h.session.connection == .connected && h.session.state[CoreProps.brightness] == 11 }
        #expect(h.session.state[CoreProps.brightness] == 11, "state refreshed on reconnect")
        await h.stop()
    }

    @Test func cancellationDisconnects() async {
        let h = await SessionHarness()
        h.runner.cancel()
        await settle { h.fake.disconnectCount == 1 }
        #expect(h.fake.disconnectCount == 1, "back = disconnect")
    }

    @Test func staleQueuedReadCannotRevertAWrite() async {
        let h = await SessionHarness()
        h.fake.deferReads = true
        h.session.refresh()  // reads queue device-side, capturing pre-write values
        h.session.set(CoreProps.speed, to: 9.9)
        await settle { h.fake.written.contains { $0.id == CoreProps.speed.id } }
        h.fake.deliverPendingReads()  // stale responses arrive after the ack
        try? await Task.sleep(for: .milliseconds(50))
        #expect(h.session.state[CoreProps.speed] == 9.9, "stale read must not revert the written value")

        h.fake.inject(.valueRead(CoreProps.speed.id, "1.5"))  // later, genuinely fresh read
        await settle { h.session.state[CoreProps.speed] == 1.5 }
        #expect(h.session.state[CoreProps.speed] == 1.5, "staleness tracking settles; new reads apply")
        await h.stop()
    }

    @Test func incompatibleDeviceStopsReconnecting() async {
        let fake = FakeCoreLink()  // no props: bare link we drive by hand
        let session = CoreSession(link: fake, throttle: .milliseconds(10))
        let runner = Task { await session.run() }
        await settle { fake.connectCount == 1 }
        fake.inject(.incompatible(CoreLinkError("Device has no ShinerCore service")))
        fake.inject(.disconnected(reason: nil))  // the cancel that follows
        try? await Task.sleep(for: .milliseconds(50))
        #expect(session.connection == .failed("Device has no ShinerCore service"))
        #expect(fake.connectCount == 1, "no reconnect attempts against an incompatible device")
        runner.cancel()
        await settle { fake.disconnectCount > 0 }
    }

    @Test func notificationAppliesWhenClean() async {
        let h = await SessionHarness()
        h.fake.inject(.valueChanged(CoreProps.brightness.id, "77"))
        await settle { h.session.state[CoreProps.brightness] == 77 }
        #expect(h.session.state[CoreProps.brightness] == 77, "device-side change (other phone, cursor fanout) shows up live")
        await h.stop()
    }

    @Test func notificationDroppedWhileDirtyAndCountingUnaffected() async {
        let h = await SessionHarness()
        h.session.set(CoreProps.brightness, to: 42)
        h.fake.inject(.valueChanged(CoreProps.brightness.id, "180"))  // our own write echoing back mid-drag
        await settle { h.fake.written.contains { $0.id == CoreProps.brightness.id } }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(h.session.state[CoreProps.brightness] == 42, "echo must not yank the slider")

        // Notifications carry no read bookkeeping: a later refresh still settles.
        h.fake.values[CoreProps.brightness.id] = "99"
        h.session.refresh()
        await settle { h.session.state[CoreProps.brightness] == 99 }
        #expect(h.session.state[CoreProps.brightness] == 99)
        await h.stop()
    }

    @Test func wiringDocsDecodeIntoState() async {
        let h = await SessionHarness(fake: .demo(board: .atomLite))
        await settle { h.session.state.wiringDocs != nil }
        #expect(h.session.state.wiringDocs?.board == "atom-lite")
        #expect(h.session.state.wiringDocs?.analogPins == ["G33", "G32"])
        await h.stop()
    }

    @Test func wiringWriteRereadsOnceOnRevisionChange() async throws {
        let h = await SessionHarness()
        await settle { h.session.state[CoreProps.pinStatus] != nil && h.session.state[CoreProps.wiring] != nil }
        let wiringReads = { h.fake.readRequests.count { $0 == CoreProps.wiring.id } }
        let before = wiringReads()

        h.fake.inject(.valueChanged(CoreProps.pinStatus.id, "07003c9e"))  // button released, same revision
        try await Task.sleep(for: .milliseconds(50))
        #expect(wiringReads() == before, "live pin changes alone don't re-read wiring")

        var wiring = try #require(h.session.state[CoreProps.wiring])
        wiring["G25"] = .switch(.lightsOn)
        h.session.set(CoreProps.wiring, to: wiring)
        await settle { wiringReads() > before }
        try await Task.sleep(for: .milliseconds(50))
        #expect(wiringReads() == before + 1)
        #expect(h.session.state[CoreProps.pinStatus]?.revision == 8)
        await h.stop()
    }

    @Test func rejectedWiringWriteSurfacesAnError() async throws {
        let h = await SessionHarness()
        await settle { h.session.state[CoreProps.pinStatus] != nil && h.session.state[CoreProps.wiring] != nil }
        let original = try #require(h.session.state[CoreProps.wiring])
        h.fake.rejectWiringWrites = true
        var wiring = original
        wiring["G25"] = .switch(.lightsOn)
        h.session.set(CoreProps.wiring, to: wiring)
        await settle { h.session.lastError != nil }
        #expect(h.session.lastError?.contains("rejected") == true)
        #expect(h.session.state[CoreProps.wiring] == original)
        await h.stop()
    }

    @Test func acceptedWiringWriteRaisesNoError() async throws {
        let h = await SessionHarness()
        await settle { h.session.state[CoreProps.pinStatus] != nil && h.session.state[CoreProps.wiring] != nil }
        let reads = h.fake.readRequests.count
        var wiring = try #require(h.session.state[CoreProps.wiring])
        wiring["G25"] = .switch(.lightsOn)
        h.session.set(CoreProps.wiring, to: wiring)
        await settle { h.fake.readRequests.count > reads }
        await settle(timeout: .milliseconds(200)) { false }  // let the read-back land
        #expect(h.session.lastError == nil)
        #expect(h.session.state[CoreProps.wiring] == wiring)
        await h.stop()
    }

    @Test func revisionChangeAppliesDeviceWiring() async throws {
        let h = await SessionHarness()
        await settle { h.session.state[CoreProps.pinStatus] != nil && h.session.state[CoreProps.wiring] != nil }
        // The firmware rejected or reset a write: same revision bump, different wiring.
        h.fake.values[CoreProps.wiring.id] = #"{"G26":{"leds":true}}"#
        h.fake.inject(.valueChanged(CoreProps.pinStatus.id, "08013c9e"))
        await settle { h.session.state[CoreProps.wiring] == Wiring(["G26": .leds]) }
        #expect(h.session.state[CoreProps.wiring] == Wiring(["G26": .leds]))
        await h.stop()
    }

    @Test func malformedPinStatusSurfaces() async {
        let h = await SessionHarness()
        h.fake.inject(.valueChanged(CoreProps.pinStatus.id, "zz"))
        await settle { h.session.lastError != nil }
        #expect(h.session.lastError?.contains("pin status") == true)
        await h.stop()
    }

    @Test func writeFailureSurfaces() async {
        let h = await SessionHarness()
        h.fake.writeError = CoreLinkError("device said no")
        h.session.set(CoreProps.brightness, to: 5)
        await settle { h.session.lastError != nil }
        #expect(h.session.lastError?.contains("brightness") == true)
        await h.stop()
    }
}
