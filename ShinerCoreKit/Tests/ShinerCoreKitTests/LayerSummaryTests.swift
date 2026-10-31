import Testing
import Foundation
import SwiftUI  // MutableCollection.move(fromOffsets:toOffset:), as List uses it
@testable import ShinerCoreKit

struct LayerSummaryTests {
    let docs = try! Documentation(json: FakeCoreLink.demoDocumentation)

    @Test func decodesTheContractExample() throws {
        let summary = try LayerSummary(wire: "P 1\n0 11 0 ff6400 f0ff00 6 6 4 0 1", documentation: docs)
        #expect(summary.source == .preset(1))
        #expect(summary.layers == [LayerSummary.Layer(index: 0, look: LayerLook(
            animation: "Gradient Pulse", blendMode: "Add",
            color1: PixelColor(r: 255, g: 100, b: 0), color2: PixelColor(r: 240, g: 255, b: 0),
            speed: 6, beatSynced: false, tau: 6, phi: 4))])
    }

    @Test func decodesANeighborsPresetWithBeatSyncAndClosedGate() throws {
        let summary = try LayerSummary(wire: "M\n2 6 8 ffffff 000000 2.5 -0.125 10 1 0\n", documentation: docs)
        #expect(summary.source == .neighbor)
        let layer = try #require(summary.layers.first)
        #expect(layer.index == 2 && layer.look.animation == "Comet" && layer.look.blendMode == "Screen")
        #expect(layer.look.beatSynced && !layer.gateOpen)
        #expect(layer.look.speed == 2.5 && layer.look.tau == -0.125)
    }

    @Test func decodesAnEmptyStack() throws {
        let summary = try LayerSummary(wire: "P 4", documentation: docs)
        #expect(summary == LayerSummary(source: .preset(4), layers: []))
        #expect(summary.firstEmptySlot == 0)
    }

    @Test(arguments: [
        ("", LayerSummaryError(line: 1, text: "", reason: "expected \"P n\" or \"M\"")),
        ("P 5", LayerSummaryError(line: 1, text: "P 5", reason: "the preset must be 0-4")),
        ("P 1\n0 11 0 ff6400 f0ff00 6 6 4 0", LayerSummaryError(
            line: 2, text: "0 11 0 ff6400 f0ff00 6 6 4 0", reason: "expected 10 fields, found 9")),
        ("P 1\n0 1 0 ffffff 000000 1 1 1 0 1\n1 14 0 ffffff 000000 1 1 1 0 1", LayerSummaryError(
            line: 3, text: "1 14 0 ffffff 000000 1 1 1 0 1", reason: "animation must be 0-13, not 14")),
        ("P 1\n0 1 0 fff 000000 1 1 1 0 1", LayerSummaryError(
            line: 2, text: "0 1 0 fff 000000 1 1 1 0 1", reason: "color must be rrggbb, not fff")),
        ("P 1\n0 1 0 ffffff 000000 fast 1 1 0 1", LayerSummaryError(
            line: 2, text: "0 1 0 ffffff 000000 fast 1 1 0 1", reason: "speed is not a number: fast")),
        ("P 1\n3 1 0 ffffff 000000 1 1 1 0 1\n3 1 0 ffffff 000000 1 1 1 0 1", LayerSummaryError(
            line: 3, text: "3 1 0 ffffff 000000 1 1 1 0 1", reason: "layer 3 comes after layer 3; layers must be bottom first")),
        ("P 1\n\n0 1 0 ffffff 000000 1 1 1 0 1", LayerSummaryError(
            line: 2, text: "", reason: "expected 10 fields, found 0")),
    ])
    func malformedValueNamesTheFailingLine(wire: String, error: LayerSummaryError) {
        #expect(throws: error) { try LayerSummary(wire: wire, documentation: docs) }
    }

    @Test func indicesNeedDocumentation() {
        #expect(throws: LayerSummaryError(line: 2, text: "0 1 0 ffffff 000000 1 1 1 0 1",
                                          reason: "animation 1 is unknown: documentation lists none")) {
            try LayerSummary(wire: "P 1\n0 1 0 ffffff 000000 1 1 1 0 1", documentation: Documentation())
        }
    }

    // MARK: - Moves

    private func stack(_ slots: [Int], gatesClosed: Set<Int> = []) -> LayerSummary {
        LayerSummary(source: .preset(0), layers: slots.map {
            LayerSummary.Layer(index: $0, look: LayerLook(animation: "A\($0)", color1: .black, color2: .black,
                                                          speed: 1, tau: 1, phi: 1),
                               gateOpen: !gatesClosed.contains($0))
        })
    }

    private func animations(_ summary: LayerSummary) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: summary.layers.map { ($0.index, $0.look.animation) })
    }

    @Test func moveShiftsTheLayersInBetween() {
        #expect(animations(stack([0, 1, 5]).moving(from: 0, to: 5)) == [0: "A1", 4: "A5", 5: "A0"])
        #expect(animations(stack([0, 1, 5]).moving(from: 5, to: 0)) == [0: "A5", 1: "A0", 2: "A1"])
    }

    @Test func gatesStayWithTheirSlot() {
        let moved = stack([0, 1], gatesClosed: [1]).moving(from: 0, to: 1)
        #expect(moved.layer(at: 1)?.look.animation == "A0")
        #expect(moved.layer(at: 1)?.gateOpen == false)
        #expect(moved.layer(at: 0)?.gateOpen == true)
    }

    /// The list shows front-most first, so the rows of slots 0, 1, 5 read 5, 1, 0.
    @Test func listMovesMapToLayerMoves() {
        let summary = stack([0, 1, 5])
        #expect(summary.layerMove(fromRow: 2, toRow: 0)! == (0, 5), "bottom to the front")
        #expect(summary.layerMove(fromRow: 0, toRow: 3)! == (5, 0), "front to the bottom")
        #expect(summary.layerMove(fromRow: 0, toRow: 2)! == (5, 1), "front to just behind the middle")
        #expect(summary.layerMove(fromRow: 2, toRow: 1)! == (0, 1), "bottom to just in front of the middle")
        #expect(summary.layerMove(fromRow: 1, toRow: 1) == nil)
        #expect(summary.layerMove(fromRow: 1, toRow: 2) == nil)
    }

    @Test(arguments: [(2, 0), (0, 3), (0, 2), (2, 1), (1, 0), (1, 3)])
    func aListMoveOrdersTheStackAsTheListShowsIt(source: Int, destination: Int) throws {
        let summary = stack([0, 1, 5])
        var rows = summary.layers.reversed().map(\.look.animation)
        rows.move(fromOffsets: [source], toOffset: destination)
        let move = try #require(summary.layerMove(fromRow: source, toRow: destination))
        #expect(summary.moving(from: move.from, to: move.to).layers.reversed().map(\.look.animation) == rows)
    }

    @Test func decodesTheOpacitiesContractExample() throws {
        #expect(try LayerSummary.opacities(wire: "1 0.3 1 1 1 1 1 1 1 0") == [1, 0.3, 1, 1, 1, 1, 1, 1, 1, 0])
    }

    @Test(arguments: [
        ("1 1 1 1 1 1 1 1 1", "layerOpacities must list 10 opacities, found 9"),
        ("1 1 1 1 1 1 1 1 1 1 1", "layerOpacities must list 10 opacities, found 11"),
        ("1 1  1 1 1 1 1 1 1", "layerOpacities slot 2 is not a number: \"\""),
        ("1 1 1 half 1 1 1 1 1 1", "layerOpacities slot 3 is not a number: \"half\""),
        ("1 1 1 1 nan 1 1 1 1 1", "layerOpacities slot 4 is not a number: \"nan\""),
        ("1 1 1 1 1 1.5 1 1 1 1", "layerOpacities slot 5 must be 0-1, not 1.5"),
        ("1 1 1 1 1 1 -0.1 1 1 1", "layerOpacities slot 6 must be 0-1, not -0.1"),
    ])
    func malformedOpacitiesNameTheProblem(wire: String, reason: String) {
        #expect(throws: LayerSummaryError(line: 1, text: wire, reason: reason)) {
            try LayerSummary.opacities(wire: wire)
        }
    }

    @Test func opacitiesLandOnTheirSlots() throws {
        var summary = stack([0, 3, 7])
        summary.apply(opacities: [1, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9])
        #expect(summary.layers.map(\.look.opacity) == [1, 0.3, 0.7])
    }

    @Test func wiringNoticeNamesControlsWhoseLayerChanged() throws {
        let docs = try WiringDocs(json: #"{"board":"atom-lite","pins":["G21","G25","G22","G19","G23","G33","G26","G32"],"frontButton":"G39","analog":["G33","G32"],"led":["G26","G32"],"claims":{},"targets":["tau"]}"#)
        let wiring = Wiring(["G23": .switch(.layerOn(1)), "G33": .knob(Knob(target: .tau, layer: 5, min: 0, max: 1)),
                             "G39": .button(.toggleLayer(4)), "G21": .button(.toggleLayer(0))])
        let before = stack([0, 1, 5])
        let after = before.moving(from: 0, to: 5)
        #expect(LayerSummary.wiringNotice(before: before, after: after, wiring: wiring, docs: docs)
            == "The button on G21 now controls A1. The switch on G23 now controls an empty layer. The front button now controls A5. The knob on G33 now controls A0.")
        let unwired = stack([0, 1, 5, 7, 8])
        #expect(LayerSummary.wiringNotice(before: unwired, after: unwired.moving(from: 7, to: 8),
                                          wiring: wiring, docs: docs) == nil)
    }
}
