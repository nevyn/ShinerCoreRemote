import Testing
import Foundation
@testable import ShinerCoreKit

@Suite @MainActor struct LayerSessionTests {
    private func animations(_ layers: [LayerSummary.Layer]?) -> [String] {
        (layers ?? []).map(\.look.animation)
    }

    private func written(_ fake: FakeCoreLink) -> [String] {
        fake.written.map { "\(CoreProps.name(of: $0.id)) \($0.raw)" }
    }

    @Test func connectReadsTheStack() async {
        let h = await SessionHarness()
        #expect(animations(h.session.state.stack) == ["Gradient Pulse", "Comet", "Sparkle"])
        #expect(h.session.state.playingLayers == h.session.state.stack)
        #expect(!h.fake.readRequests.contains(CoreProps.layerMove.id), "layerMove is write-only")
        await h.stop()
    }

    @Test func revisionChangeRereadsTheStack() async {
        let h = await SessionHarness()
        h.fake.setLayer(FakeCoreLink.layer("Rainbow", color: "0 0 0", speed: 3), preset: 1, slot: 5)
        await settle { h.session.state.stack?.count == 4 }
        #expect(animations(h.session.state.stack) == ["Gradient Pulse", "Comet", "Sparkle", "Rainbow"])
        await h.stop()
    }

    /// The core applies per-layer writes to the layer under its cursor when they arrive, so
    /// an edit still in its throttle interval must reach the core before a cursor move.
    @Test func throttledEditLandsBeforeTheCursorMoves() async throws {
        let h = await SessionHarness()
        h.session.set(CoreProps.speed, to: 7)  // layer 0, throttled
        h.session.selectLayer(2)
        h.session.set(CoreProps.speed, to: 9)  // layer 2
        await settle { h.fake.written.count == 3 }
        #expect(written(h.fake) == ["speed 7.0", "layer 2", "speed 9.0"])
        #expect(h.fake.presets[1][0][CoreProps.speed.id] == "7.0")
        #expect(h.fake.presets[1][2][CoreProps.speed.id] == "9.0")
        await h.stop()
    }

    @Test func editAfterAFailedCursorMoveNeverReachesTheCore() async throws {
        let h = await SessionHarness()
        h.fake.writeErrors[CoreProps.layer.id] = CoreLinkError("device said no")
        h.session.selectLayer(2)
        h.session.set(CoreProps.speed, to: 9)  // throttled, meant for layer 2
        await settle { h.session.lastError != nil }
        try await Task.sleep(for: .milliseconds(100))  // ten throttle intervals
        #expect(!h.fake.written.contains { $0.id == CoreProps.speed.id }, "\(written(h.fake))")
        #expect(h.fake.presets[1][0][CoreProps.speed.id] == "2.500", "the previous layer is untouched")
        #expect(h.session.lastError == "Couldn't set layer: device said no. The change after it wasn't sent.")
        await h.stop()
    }

    @Test func perLayerReadFromBeforeACursorMoveDoesNotLand() async throws {
        let h = await SessionHarness()
        h.fake.republishesCursorLayer = false
        h.fake.deferReads = true
        h.session.refresh()  // per-layer reads capture layer 0's values
        h.session.selectLayer(1)
        h.fake.deliverPendingReads()  // layer 0's answers arrive around the move
        await settle { !h.fake.written.isEmpty }
        try await Task.sleep(for: .milliseconds(50))
        #expect(h.session.state[CoreProps.animation] == "Comet", "from the summary, not layer 0's Gradient Pulse")
        #expect(h.session.state.rawValue(of: CoreProps.color) == "255 255 255")
        await h.stop()
    }

    @Test func perLayerReadFromBeforeAPresetSwitchDoesNotLand() async throws {
        let h = await SessionHarness()
        h.fake.republishesCursorLayer = false
        h.fake.deferReads = true
        h.session.refresh()
        h.session.selectPreset(2)
        h.fake.deliverPendingReads()
        await settle { !h.fake.written.isEmpty }
        try await Task.sleep(for: .milliseconds(50))
        #expect(h.session.state[CoreProps.animation] == nil, "loading, not preset 1's Gradient Pulse")
        await h.stop()
    }

    @Test func selectingShowsTheLayerAtOnceAndKeepsItOnceRead() async {
        let h = await SessionHarness()
        h.session.selectLayer(1)
        #expect(h.session.state[CoreProps.animation] == "Comet", "from the summary, before the core answers")
        #expect(h.session.state[CoreProps.blendMode] == "Screen")
        await settle { h.fake.written.count == 1 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(h.session.state[CoreProps.animation] == "Comet")
        #expect(h.session.state[CoreProps.layer] == 1)
        await h.stop()
    }

    @Test func addFillsTheFirstEmptySlotWithStatic() async {
        let h = await SessionHarness()
        h.fake.setLayer(FakeCoreLink.layer("Static", color: "0 0 255", speed: 1), preset: 1, slot: 0)
        await settle { h.session.state.stack?.first?.look.animation == "Static" }
        // The cursor's layer already plays Static; the new slot must still get it.
        #expect(h.session.addLayer() == 3)
        await settle { h.fake.written.count == 2 }
        #expect(written(h.fake) == ["layer 3", "animation Static"])
        await settle { h.session.state.stack?.count == 4 }
        #expect(animations(h.session.state.stack) == ["Static", "Comet", "Sparkle", "Static"])
        await h.stop()
    }

    @Test func addIsUnavailableWhenAllTenAreUsed() async {
        let fake = FakeCoreLink.demo()
        for slot in 0 ..< CoreProps.layerCount {
            fake.setLayer(FakeCoreLink.layer("Twinkle", color: "255 255 255", speed: 1), preset: 1, slot: slot)
        }
        let h = await SessionHarness(fake: fake)
        #expect(h.session.addLayer() == nil)
        await h.stop()
    }

    @Test func removeEmptiesTheLayerWithoutFlickering() async {
        let h = await SessionHarness()
        h.session.removeLayer(1)
        #expect(animations(h.session.state.stack) == ["Gradient Pulse", "Sparkle"], "optimistic")
        var seen: [[String]] = []
        for _ in 0 ..< 40 {
            seen.append(animations(h.session.state.stack))
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(seen.allSatisfy { $0 == ["Gradient Pulse", "Sparkle"] }, "\(seen)")
        #expect(written(h.fake) == ["layer 1", "animation Nothing"])
        #expect(h.fake.presets[1][1][CoreProps.animation.id] == "Nothing")
        await h.stop()
    }

    @Test func moveReordersAtOnceAndSaysWhatWiringNowControls() async throws {
        let fake = FakeCoreLink.demo(board: .atomLite)  // knob on G33 writes layer 2's hue
        fake.values[CoreProps.preset.id] = "1"
        let h = await SessionHarness(fake: fake)
        h.session.moveLayer(from: 0, to: 2)
        #expect(animations(h.session.state.stack) == ["Comet", "Sparkle", "Gradient Pulse"], "optimistic")
        #expect(h.session.state[CoreProps.layer] == 2, "the cursor follows the moved layer")
        #expect(h.session.layerMoveNotice == "The knob on G33 now controls Gradient Pulse.")
        await settle { !h.fake.written.isEmpty }
        #expect(written(h.fake) == ["layerMove 0 2"])
        try await Task.sleep(for: .milliseconds(50))
        #expect(animations(h.session.state.stack) == ["Comet", "Sparkle", "Gradient Pulse"])
        #expect(h.session.state[CoreProps.animation] == "Gradient Pulse")
        await h.stop()
    }

    @Test func presetSwitchNeverShowsTheOldPresetsLayer() async {
        let h = await SessionHarness()
        h.session.selectPreset(2)
        #expect(h.session.state[CoreProps.animation] == nil, "loading, not Gradient Pulse")
        #expect(h.session.state.stack == nil)
        await settle { h.session.state[CoreProps.animation] != nil && h.session.state.stack != nil }
        #expect(animations(h.session.state.stack) == ["Scanner"])
        #expect(h.session.state[CoreProps.animation] == "Scanner")
        await h.stop()
    }

    @Test func aNeighborsPresetPlaysButTheStackStaysOwn() async {
        let h = await SessionHarness()
        h.fake.neighborLayers = [FakeCoreLink.layer("Rainbow", color: "0 0 0", speed: 3)]
        await settle { h.session.state.layerSummary?.source == .neighbor }
        #expect(animations(h.session.state.playingLayers) == ["Rainbow"])
        #expect(animations(h.session.state.stack) == ["Gradient Pulse", "Comet", "Sparkle"])
        await h.stop()
    }

    @Test func editsShowInTheStackBeforeTheSummaryCatchesUp() async {
        let h = await SessionHarness()
        h.session.set(CoreProps.blendMode, to: "Multiply")
        #expect(h.session.state.stack?.first?.look.blendMode == "Multiply")
        #expect(h.session.state.layerSummary?.layers.first?.look.blendMode == "Add")
        await h.stop()
    }

    @Test func opacityEditShowsInTheStackLikeASpeedEdit() async {
        let h = await SessionHarness()
        h.session.set(CoreProps.opacity, to: 0.25)
        #expect(h.session.state.stack?.first?.look.opacity == 0.25)
        #expect(h.session.state.layerSummary?.layers.first?.look.opacity == 1)
        await settle { h.session.state.layerSummary?.layers.first?.look.opacity == 0.25 }
        #expect(written(h.fake) == ["opacity 0.25"])
        #expect(h.session.state.layerSummary?.layers.first?.look.opacity == 0.25, "the revision brought the core's opacities")
        await h.stop()
    }

    @Test func opacitiesLandOnTheirLayersAndFollowTheCursor() async {
        let fake = FakeCoreLink.demo()
        fake.setLayer(FakeCoreLink.layer("Comet", blend: "Screen", color: "255 255 255", speed: 1.8, opacity: 0.3), preset: 1, slot: 1)
        let h = await SessionHarness(fake: fake)
        #expect(h.session.state.layerSummary?.layers.map(\.look.opacity) == [1, 0.3, 1])
        h.session.selectLayer(1)
        #expect(h.session.state[CoreProps.opacity] == 0.3, "from the summary, before the core answers")
        await h.stop()
    }

    @Test func coreWithoutOpacityComposesFullyAndStillShowsEdits() async {
        let fake = FakeCoreLink.demo()
        fake.values[CoreProps.opacity.id] = nil
        fake.values[CoreProps.layerOpacities.id] = nil
        let h = await SessionHarness(fake: fake)
        #expect(h.session.state.layerSummary?.layers.map(\.look.opacity) == [1, 1, 1])
        h.session.set(CoreProps.blendMode, to: "Multiply")
        #expect(h.session.state.stack?.first?.look.blendMode == "Multiply")
        await h.stop()
    }

    @Test func malformedOpacitiesSurfaceAndFallBack() async {
        let h = await SessionHarness()
        h.fake.inject(.valueChanged(CoreProps.layerOpacities.id, "1 2 1 1 1 1 1 1 1 1"))
        await settle { h.session.lastError != nil }
        #expect(h.session.lastError?.contains("layerOpacities slot 1 must be 0-1, not 2") == true, "\(h.session.lastError ?? "")")
        #expect(h.session.state.layerSummary == nil)
        await h.stop()
    }

    @Test func malformedSummarySurfacesAndFallsBack() async {
        let h = await SessionHarness()
        h.fake.inject(.valueChanged(CoreProps.layers.id, "P 1\n0 99 0 ffffff 000000 1 1 1 0 1"))
        await settle { h.session.lastError != nil }
        #expect(h.session.lastError?.contains("line 2") == true, "\(h.session.lastError ?? "")")
        #expect(h.session.state.layerSummaryError?.line == 2)
        #expect(h.session.state.layerSummary == nil)
        await h.stop()
    }

    @Test func failedSummaryReadFallsBackUntilARevisionBringsItBack() async {
        let fake = FakeCoreLink.demo()
        fake.readErrors[CoreProps.layers.id] = CoreLinkError("Reading is not permitted.")
        let session = CoreSession(link: fake, throttle: .milliseconds(10))
        let runner = Task { await session.run() }
        await settle { session.state.layerSummaryReadFailed }
        #expect(session.state.layerSummaryReadFailed)
        #expect(session.state.layerSummary == nil)

        fake.readErrors = [:]
        fake.setLayer(FakeCoreLink.layer("Rainbow", color: "0 0 0", speed: 3), preset: 1, slot: 5)  // bumps the revision
        await settle { session.state.stack?.count == 4 }
        #expect(!session.state.layerSummaryReadFailed)
        #expect(animations(session.state.stack) == ["Gradient Pulse", "Comet", "Sparkle", "Rainbow"])
        runner.cancel()
        await settle { fake.disconnectCount > 0 }
    }

    @Test func outstandingSummaryReadIsNotAFailure() async {
        let fake = FakeCoreLink.demo()
        fake.deferReads = true
        let session = CoreSession(link: fake, throttle: .milliseconds(10))
        let runner = Task { await session.run() }
        await settle { fake.readRequests.contains(CoreProps.layers.id) }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(session.state.layerSummary == nil)
        #expect(!session.state.layerSummaryReadFailed, "still loading")
        runner.cancel()
        await settle { fake.disconnectCount > 0 }
    }

    @Test func failedCursorWriteKeepsDependentWritesBack() async {
        let h = await SessionHarness()
        h.fake.writeError = CoreLinkError("device said no")
        h.session.addLayer()
        await settle { h.session.lastError != nil }
        #expect(h.session.lastError == "Couldn't set layer: device said no. The change after it wasn't sent.")
        #expect(h.fake.presets[1][3][CoreProps.animation.id] == "Nothing")
        await h.stop()
    }
}

extension CoreProps {
    /// The property's name, for readable test expectations.
    static func name(of id: PropertyID) -> String {
        let keys: [(PropertyID, String)] = [
            (layer.id, layer.name), (preset.id, preset.name), (layerMove.id, layerMove.name),
            (animation.id, animation.name), (speed.id, speed.name), (color.id, color.name),
            (blendMode.id, blendMode.name), (opacity.id, opacity.name),
        ]
        return keys.first { $0.0 == id }?.1 ?? id.description
    }
}
