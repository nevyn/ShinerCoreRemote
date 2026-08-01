import Testing
import SwiftUI
@testable import ShinerCoreKit

@Suite struct ConverterTests {
    @Test func intRoundTrip() {
        #expect(IntConverter.convert("42") == 42)
        #expect(IntConverter.unconvert(42) == "42")
        #expect(IntConverter.convert("nope") == nil)
    }

    @Test func doubleRoundTrip() {
        #expect(DoubleConverter.convert("2.5") == 2.5)
        #expect(DoubleConverter.convert("") == nil)
        #expect(DoubleConverter.convert(DoubleConverter.unconvert(0.01)) == 0.01)
    }

    @Test func colorParsing() {
        #expect(ColorConverter.convert("255 40 120") != nil)
        #expect(ColorConverter.convert("256 0 0") == nil)
        #expect(ColorConverter.convert("1 2") == nil)
        #expect(ColorConverter.convert("a b c") == nil)
    }

    @Test func colorRoundTripIsStable() throws {
        // Write-then-read-back must not oscillate: unconvert(convert(x)) == x.
        for wire in ["0 0 0", "255 255 255", "255 40 120", "1 2 3", "128 128 128"] {
            let color = try #require(ColorConverter.convert(wire))
            #expect(ColorConverter.unconvert(color) == wire)
        }
    }

    @Test func colorWideGamutClampsToWireRange() throws {
        // Display P3 red is outside sRGB; components must clamp to 0...255.
        let wire = ColorConverter.unconvert(Color(.displayP3, red: 1, green: 0.2, blue: 0))
        let components = wire.components(separatedBy: " ").map { Int($0) }
        #expect(components.count == 3)
        for component in components {
            let c = try #require(component)
            #expect((0...255).contains(c))
        }
    }

    @Test func documentationDecoding() {
        let doc = DocumentationConverter.convert(
            #"{"blendModes":["add"],"animations":["rainbow","pulse"],"ledColorOrders":["RGB"]}"#)
        #expect(doc == Documentation(blendModes: ["add"], animations: ["rainbow", "pulse"], ledColorOrders: ["RGB"]))
    }

    @Test func documentationToleratesMissingKeys() {
        let doc = DocumentationConverter.convert(#"{"animations":["solid"]}"#)
        #expect(doc == Documentation(animations: ["solid"]))
        #expect(DocumentationConverter.convert("not json") == nil)
    }

    @Test func propertyIDNormalizesCase() {
        #expect(PropertyID("c116fce1-9a8a-4084-80a3-b83be2fbd108") == PropertyID("C116FCE1-9A8A-4084-80A3-B83BE2FBD108"))
    }
}
