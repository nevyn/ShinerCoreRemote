import Testing
import Foundation
@testable import ShinerCoreKit

/// The fake firmware stands in for a core in demo mode, so it must behave like one.
@Suite @MainActor struct FakeCoreLinkTests {
    /// Collects the fake's events as they are emitted.
    @MainActor final class EventLog {
        var events: [CoreLinkEvent] = []
        private var task: Task<Void, Never>?

        init(_ fake: FakeCoreLink) {
            task = Task { for await event in fake.events { self.events.append(event) } }
        }

        func changes(of id: PropertyID) -> [String] {
            events.compactMap { if case .valueChanged(id, let raw) = $0 { raw } else { nil } }
        }

        deinit { task?.cancel() }
    }

    let docs = try! Documentation(json: FakeCoreLink.demoDocumentation)

    private func summary(_ fake: FakeCoreLink) throws -> LayerSummary {
        try LayerSummary(wire: try #require(fake.values[CoreProps.layers.id]), documentation: docs)
    }

    @Test func demoStacksThreeLayersOnPresetOne() throws {
        let summary = try summary(.demo())
        #expect(summary.source == .preset(1))
        #expect(summary.layers.map(\.look.animation) == ["Gradient Pulse", "Comet", "Sparkle"])
        #expect(summary.layers.map(\.look.blendMode) == ["Add", "Screen", "Add"])
        #expect(FakeCoreLink.demo().values[CoreProps.animation.id] == "Gradient Pulse")
    }

    @Test func perLayerPropertiesFollowTheCursor() async throws {
        let fake = FakeCoreLink.demo()
        let log = EventLog(fake)
        try await fake.write("1", to: CoreProps.layer.id)
        #expect(fake.values[CoreProps.animation.id] == "Comet")
        try await fake.write("255 0 0", to: CoreProps.color.id)
        #expect(try summary(fake).layer(at: 1)?.look.color1 == PixelColor(r: 255, g: 0, b: 0))
        #expect(try summary(fake).layer(at: 0)?.look.color1 == PixelColor(r: 255, g: 40, b: 120))
        await settle { !log.changes(of: CoreProps.perLayer.last!).isEmpty }  // the last one republished
        #expect(log.changes(of: CoreProps.animation.id) == ["Comet"], "a cursor move republishes per-layer properties")
        #expect(log.changes(of: CoreProps.blendMode.id) == ["Screen"])
    }

    @Test func presetCursorSwitchesStacks() async throws {
        let fake = FakeCoreLink.demo()
        try await fake.write("2", to: CoreProps.preset.id)
        #expect(try summary(fake) == LayerSummary(source: .preset(2), layers: [LayerSummary.Layer(index: 0, look: LayerLook(
            animation: "Scanner", color1: PixelColor(r: 255, g: 0, b: 0), color2: .black, speed: 1.5, tau: 4, phi: 3))]))
        #expect(fake.values[CoreProps.animation.id] == "Scanner")
    }

    @Test func layerEditsBumpTheRevisionAndNotify() async throws {
        let fake = FakeCoreLink.demo()
        let log = EventLog(fake)
        let before = try #require(fake.values[CoreProps.layersRevision.id].flatMap(Int.init))
        try await fake.write("4.000", to: CoreProps.speed.id)
        try await fake.write("4.000", to: CoreProps.speed.id)  // unchanged: no bump
        try await fake.write("200", to: CoreProps.brightness.id)  // not in the summary
        #expect(fake.values[CoreProps.layersRevision.id] == String(before + 1))
        await settle { !log.changes(of: CoreProps.layersRevision.id).isEmpty }
        #expect(log.changes(of: CoreProps.layersRevision.id) == [String(before + 1)])
        #expect(try summary(fake).layer(at: 0)?.look.speed == 4)
    }

    @Test func layerMoveFollowsTheContract() async throws {
        let fake = FakeCoreLink.demo()
        try await fake.write("0 2", to: CoreProps.layerMove.id)
        #expect(try summary(fake).layers.map(\.look.animation) == ["Comet", "Sparkle", "Gradient Pulse"])
        #expect(fake.layerCursor == 2, "the cursor on FROM follows the layer")
        for malformed in ["0 10", "2", "a b", "-1 0"] {
            try await fake.write(malformed, to: CoreProps.layerMove.id)
        }
        #expect(try summary(fake).layers.map(\.look.animation) == ["Comet", "Sparkle", "Gradient Pulse"])
    }

    @Test func gatesAndTheCarouselShowInTheSummary() throws {
        let fake = FakeCoreLink.demo()
        fake.gates[1] = false
        #expect(try summary(fake).layer(at: 1)?.gateOpen == false)
        fake.neighborLayers = [FakeCoreLink.layer("Rainbow", color: "0 0 0", speed: 3)]
        #expect(try summary(fake).source == .neighbor)
        #expect(try summary(fake).layers.map(\.look.animation) == ["Rainbow"])
    }

    @Test func assigningValuesMovesCursorsWithoutCopyingLayers() throws {
        let fake = FakeCoreLink.demo()
        fake.values[CoreProps.preset.id] = "0"
        #expect(fake.values[CoreProps.animation.id] == "Breathe")
        fake.values[CoreProps.animation.id] = "Rainbow"
        #expect(fake.presets[0][0][CoreProps.animation.id] == "Rainbow")
        #expect(fake.presets[1][0][CoreProps.animation.id] == "Gradient Pulse")
    }

    @Test func olderFirmwareHasNoSummary() {
        let fake = FakeCoreLink.demo()
        fake.values[CoreProps.layers.id] = nil
        #expect(fake.values[CoreProps.layers.id] == nil && fake.values[CoreProps.layersRevision.id] == nil)
        #expect(!fake.exposesLayerSummary)
    }
}
