import Testing
import Foundation
@testable import ShinerCoreKit

struct AnimationDocsTests {
    @Test func decodesEntriesAndEmptyNames() throws {
        let docs = try AnimationDocs(json: #"[[0],[1,"Wave length"],[2,"","Glow"]]"#)
        #expect(docs.entries == [
            AnimationDoc(colors: 0, tau: nil, phi: nil),
            AnimationDoc(colors: 1, tau: "Wave length", phi: nil),
            AnimationDoc(colors: 2, tau: nil, phi: "Glow"),
        ])
    }

    @Test func malformedEntryNamesItsIndex() {
        #expect {
            try AnimationDocs(json: #"[[0],[3]]"#)
        } throws: { error in
            (error as? DecodingError)?.summary == "1: colors must be 0, 1 or 2, not 3"
        }
    }

    @Test func coreDocsComeFirst() {
        var state = CoreState()
        state.documentation = Documentation(animations: ["Nothing", "Comet"])
        state.animationDocs = AnimationDocs(entries: [AnimationDoc(colors: 0, tau: nil, phi: nil),
                                                      AnimationDoc(colors: 1, tau: "Tail", phi: nil)])
        #expect(state.animationDoc(for: "Comet") == AnimationDoc(colors: 1, tau: "Tail", phi: nil))
    }

    @Test func renderLibraryTableIsTheFallback() {
        var state = CoreState()
        state.documentation = Documentation(animations: ["Nothing"])
        state.animationDocs = AnimationDocs(entries: [AnimationDoc(colors: 0, tau: nil, phi: nil)])
        #expect(state.animationDoc(for: "Comet") == AnimationDoc(colors: 2, tau: "Tail length", phi: "Head width"))
        #expect(CoreState().animationDoc(for: "Color Wipe") == AnimationDoc(colors: 2, tau: "Wipe time", phi: nil))
        #expect(CoreState().animationDoc(for: "Rainbow").colors == 0)
    }

    @Test func unknownAnimationGetsGenericDocs() {
        #expect(CoreState().animationDoc(for: "Lava Lamp") == .generic)
    }

    @Test @MainActor func libraryTableMatchesTheFirmwaresAnimationDocs() throws {
        let docs = try AnimationDocs(json: FakeCoreLink.demoAnimationDocs)
        #expect(docs.entries == RenderLibrary.animationNames.map { RenderLibrary.animationDoc(named: $0)! })
    }
}

@Suite @MainActor struct AnimationDocsSessionTests {
    @Test func countMismatchIsReportedAndIgnored() async {
        let fake = FakeCoreLink.demo()
        fake.values[CoreProps.animationDocs.id] = #"[[0],[1]]"#
        let h = await SessionHarness(fake: fake)
        await settle { h.session.lastError != nil && h.session.state.documentation != nil }
        #expect(h.session.state.animationDocs == nil)
        let error = h.session.lastError ?? ""
        #expect(error.contains("animationDocs lists 2"), "\(error)")
        await h.stop()
    }

    @Test func malformedAnimationDocsNameTheFailingEntry() async {
        let fake = FakeCoreLink.demo()
        fake.values[CoreProps.animationDocs.id] = #"[[0],["two"]]"#
        let h = await SessionHarness(fake: fake)
        await settle { h.session.lastError != nil }
        #expect(h.session.state.animationDocs == nil)
        let error = h.session.lastError ?? ""
        #expect(error.contains("animationDocs (1.0:"), "\(error)")
        await h.stop()
    }

    @Test func demoCoreDocsArrive() async {
        let h = await SessionHarness()
        await settle { h.session.state.animationDocs != nil }
        #expect(h.session.state.animationDoc(for: "Single Wave") == AnimationDoc(colors: 1, tau: "Wave length", phi: "Phase"))
        #expect(h.session.lastError == nil)
        await h.stop()
    }
}

struct StripRendererTests {
    let red = PixelColor(r: 200, g: 10, b: 30)
    let blue = PixelColor(r: 0, g: 0, b: 255)

    @Test func staticRendersColor1Everywhere() throws {
        let look = LayerLook(animation: "Static", color1: red, color2: blue, speed: 2, tau: 1, phi: 1)
        let pixels = try #require(StripRenderer.render([look], seconds: 1.3, pixelCount: 12))
        #expect(pixels == Array(repeating: red, count: 12))
    }

    @Test func oversizedPixelCountIsClamped() throws {
        let look = LayerLook(animation: "Static", color1: red, color2: blue, speed: 2, tau: 1, phi: 1)
        let pixels = try #require(StripRenderer.render([look], seconds: 0, pixelCount: Int.max))
        #expect(pixels.count == CoreProps.maxLEDCount)
    }

    @Test func unknownAnimationRendersNothing() {
        let look = LayerLook(animation: "Lava Lamp", color1: red, color2: blue, speed: 2, tau: 1, phi: 1)
        #expect(StripRenderer.render([look], seconds: 0, pixelCount: 12) == nil)
    }

    @Test func beatSyncPlaysAt120bpm() throws {
        var look = LayerLook(animation: "Comet", color1: red, color2: blue, speed: 4, tau: 3, phi: 1)
        #expect(look.secondsPerCycle == 4)
        let free = try #require(StripRenderer.render([look], seconds: 1, pixelCount: 30))
        look.beatSynced = true
        #expect(look.secondsPerCycle == 2)
        let synced = try #require(StripRenderer.render([look], seconds: 1, pixelCount: 30))
        #expect(free != synced)
        // 4 beats at 120 bpm: 1 s into a beat-synced layer is 2 s into a free-running one.
        look.beatSynced = false
        #expect(synced == StripRenderer.render([look], seconds: 2, pixelCount: 30))
    }

    @Test func beatEnvelopePeaksOnTheBeat() {
        #expect(StripRenderer.beatEnvelope(at: 1.0) == 1)
        #expect(StripRenderer.beatEnvelope(at: 1.4) < 0.1)
    }

    @Test func layerLookReadsWireValues() {
        var state = CoreState()
        state.raw[CoreProps.animation.id] = "Comet"
        state.raw[CoreProps.color.id] = "200 10 30"
        state.raw[CoreProps.speed.id] = "2.500"
        state.raw[CoreProps.beatSync.id] = "1"
        let look = state.layerLook
        #expect(look?.color1 == red)
        #expect(look?.color2 == .black)
        #expect(look?.speed == 2.5)
        #expect(look?.beatSynced == true)
    }
}
