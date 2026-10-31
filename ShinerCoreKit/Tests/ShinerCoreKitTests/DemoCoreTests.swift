import Testing
import Foundation
@testable import ShinerCoreKit

/// The demo core is how someone without hardware tries the app, so it must work on a
/// real browser, without Bluetooth, and start clean every visit.
@Suite @MainActor struct DemoCoreTests {
    private func run(_ session: CoreSession) async -> Task<Void, Never> {
        let runner = Task { await session.run() }
        await settle { session.connection == .connected && session.state.layerSummary != nil }
        return runner
    }

    @Test func realBrowserServesTheDemoWithALayerSummary() async {
        let browser = CoreBrowser()
        let session = browser.makeSession(for: browser.demoCore)
        let runner = await run(session)
        #expect(session.connection == .connected)
        #expect(session.state.layerSummary?.layers.map(\.look.animation) == ["Gradient Pulse", "Comet", "Sparkle"])
        runner.cancel()
    }

    @Test func demoCoreIsNeverDiscovered() {
        let nearby = DiscoveredCore(id: UUID(), name: "Nevyn's jacket")
        let browser = CoreBrowser(previewCores: [(nearby, -60)])
        #expect(browser.discovered == [nearby])
        #expect(browser.signalBars[browser.demoCore.id] == nil)
        #expect(CoreBrowser().discovered.isEmpty)
    }

    @Test func previewBrowserStillServesTheDemoItself() async {
        let browser = CoreBrowser(previewCores: [], linkFactory: { _ in FakeCoreLink() })
        let session = browser.makeSession(for: browser.demoCore)
        let runner = await run(session)
        #expect(session.state.layerSummary != nil, "the demo, not the factory's empty fake")
        runner.cancel()
    }

    @Test func sessionsDoNotShareState() async {
        let browser = CoreBrowser()
        let first = browser.makeSession(for: browser.demoCore)
        let firstRunner = await run(first)
        let revision = first.state.raw[CoreProps.layersRevision.id]
        first.set(CoreProps.brightness, to: 20)
        first.removeLayer(2)
        // Brightness is flushed ahead of the layer edit, so a new revision means both landed;
        // the summary arrives with the reread that the revision triggers.
        await settle { first.state.raw[CoreProps.layersRevision.id] != revision && first.state.layerSummary?.layers.count == 2 }
        #expect(first.state.raw[CoreProps.layersRevision.id] != revision)
        #expect(first.state.layerSummary?.layers.count == 2)
        firstRunner.cancel()

        let second = browser.makeSession(for: browser.demoCore)
        let secondRunner = await run(second)
        #expect(second.state[CoreProps.brightness] == 180)
        #expect(second.state.layerSummary?.layers.count == 3)
        secondRunner.cancel()
    }
}
