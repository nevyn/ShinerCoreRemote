import Testing
@testable import ShinerCoreKit

/// Fixtures verbatim from the firmware's docs/wiring.md.
enum WiringFixtures {
    static let echoDocs = #"""
        {"board":"atom-echo",
         "pins":["G21","G25","G22","G19","G23","G33","G26","G32"],
         "analog":["G32"],
         "led":["G26","G32"],
         "claims":{"G19":"speaker","G22":"speaker","G23":"microphone","G33":"microphone"},
         "targets":["brightness","speed","tau","phi","color1.r","color1.g","color1.b",
                    "color1.h","color1.s","color1.v","color2.r","color2.g","color2.b",
                    "color2.h","color2.s","color2.v"]}
        """#
    static let liteDocs = #"""
        {"board":"atom-lite","pins":["G21","G25","G22","G19","G23","G33","G26","G32"],
         "analog":["G33","G32"],"led":["G26","G32"],
         "claims":{"G23":"microphone","G33":"microphone"},"targets":["brightness"]}
        """#
    static let example = #"""
        {"G26":{"leds":true},
         "G21":{"button":"nextPreset"},
         "G25":{"switch":"lightsOff"},
         "G22":{"switch":"preset","preset":0},
         "G23":{"switch":"layerOn","layer":3},
         "G32":{"knob":"brightness","min":0,"max":255},
         "G33":{"knob":"color1.h","layer":2,"min":0,"max":255}}
        """#
}

@Suite struct WiringTests {
    static let boardDefaults: [(String, Wiring)] = [
        (#"{"G21":{"button":"nextPreset"},"G25":{"switch":"lightsOff"},"G22":{"switch":"preset","preset":0},"G19":{"switch":"preset","preset":1},"G23":{"switch":"preset","preset":2},"G33":{"switch":"preset","preset":3},"G26":{"leds":true},"G32":{"leds":true}}"#,
         Wiring(["G21": .button(.nextPreset), "G25": .switch(.lightsOff),
                 "G22": .switch(.preset(0)), "G19": .switch(.preset(1)), "G23": .switch(.preset(2)), "G33": .switch(.preset(3)),
                 "G26": .leds, "G32": .leds])),
        (#"{"G21":{"button":"nextPreset"},"G25":{"switch":"lightsOff"},"G26":{"leds":true},"G32":{"leds":true}}"#,
         Wiring(["G21": .button(.nextPreset), "G25": .switch(.lightsOff), "G26": .leds, "G32": .leds])),
        (#"{"G39":{"button":"nextPreset"},"G38":{"switch":"lightsOff"},"G5":{"switch":"preset","preset":0},"G6":{"switch":"preset","preset":1},"G7":{"switch":"preset","preset":2},"G8":{"switch":"preset","preset":3},"G2":{"leds":true},"G1":{"leds":true}}"#,
         Wiring(["G39": .button(.nextPreset), "G38": .switch(.lightsOff),
                 "G5": .switch(.preset(0)), "G6": .switch(.preset(1)), "G7": .switch(.preset(2)), "G8": .switch(.preset(3)),
                 "G2": .leds, "G1": .leds])),
    ]

    @Test(arguments: boardDefaults)
    func boardDefaultRoundTrips(json: String, expected: Wiring) throws {
        let wiring = try Wiring(json: json)
        #expect(wiring == expected)
        #expect(try Wiring(json: wiring.json) == wiring)
    }

    @Test func contractExampleDecodes() throws {
        let wiring = try Wiring(json: WiringFixtures.example)
        #expect(wiring == Wiring([
            "G26": .leds,
            "G21": .button(.nextPreset),
            "G25": .switch(.lightsOff),
            "G22": .switch(.preset(0)),
            "G23": .switch(.layerOn(3)),
            "G32": .knob(Knob(target: .brightness, min: 0, max: 255)),
            "G33": .knob(Knob(target: .color(.primary, .hue), layer: 2, min: 0, max: 255)),
        ]))
    }

    @Test func encodesInStableOrderWithShortestNumbers() {
        let wiring = Wiring([
            "G32": .knob(Knob(target: .speed, layer: 1, min: 0.1, max: 10)),
            "G5": .button(.toggleLayer(4)),
            "G26": .leds,
        ])
        #expect(wiring.json == #"{"G5":{"button":"toggleLayer","layer":4},"G26":{"leds":true},"G32":{"knob":"speed","layer":1,"min":0.1,"max":10}}"#)
    }

    static let rejections: [(String, WiringError)] = [
        ("not json", .malformed("")),
        ("[]", .malformed("")),
        (#"{"G21":"button"}"#, .malformed("")),
        (#"{"G 21":{"leds":true}}"#, .unknownPin("G 21")),
        (#"{"G21":{"pot":"brightness"}}"#, .unknownRole(pin: "G21")),
        (#"{"G21":{"switch":"lightsOff","button":"nextPreset"}}"#, .unknownRole(pin: "G21")),
        (#"{"G26":{"leds":false}}"#, .unknownRole(pin: "G26")),
        (#"{"G21":{"button":"explode"}}"#, .unknownAction(pin: "G21", "explode")),
        (#"{"G25":{"switch":"blink"}}"#, .unknownAction(pin: "G25", "blink")),
        (#"{"G32":{"knob":"volume","min":0,"max":1}}"#, .unknownTarget(pin: "G32", "volume")),
        (#"{"G22":{"switch":"preset"}}"#, .missingKey(pin: "G22", "preset")),
        (#"{"G32":{"knob":"speed","min":1,"max":2}}"#, .missingKey(pin: "G32", "layer")),
        (#"{"G32":{"knob":"brightness","min":0}}"#, .missingKey(pin: "G32", "max")),
        (#"{"G25":{"switch":"lightsOff","preset":0}}"#, .unexpectedKey(pin: "G25", "preset")),
        (#"{"G32":{"knob":"brightness","layer":1,"min":0,"max":255}}"#, .unexpectedKey(pin: "G32", "layer")),
        (#"{"G22":{"switch":"preset","preset":5}}"#, .outOfRange(pin: "G22", "preset")),
        (#"{"G23":{"switch":"layerOn","layer":10}}"#, .outOfRange(pin: "G23", "layer")),
        (#"{"G32":{"knob":"brightness","min":0,"max":256}}"#, .outOfRange(pin: "G32", "max")),
        (#"{"G32":{"knob":"speed","layer":0,"min":0,"max":10}}"#, .outOfRange(pin: "G32", "min")),
        (#"{"G22":{"switch":"preset","preset":1.5}}"#, .malformed("")),
        (#"{"G22":{"switch":"preset","preset":"1"}}"#, .malformed("")),
    ]

    /// `.malformed` matches by case only; its detail comes from Foundation.
    @Test(arguments: rejections)
    func rejects(json: String, expected: WiringError) {
        do {
            let wiring = try Wiring(json: json)
            Issue.record("accepted \(json) as \(wiring)")
        } catch {
            if case .malformed = expected, case .malformed = error { return }
            #expect(error == expected)
        }
    }

    @Test func holdsComeFromClosedUnclaimedSwitches() throws {
        let docs = try WiringDocs(json: WiringFixtures.liteDocs)
        let wiring = try Wiring(json: Self.boardDefaults[0].0)
        // Bits: G25 (1), G22 (2), G19 (3), G23 (4) closed; G23 claimed by the microphone.
        let status = PinStatus(revision: 0, closed: 0b0001_1110, claimed: 0b0011_0000, positions: [255, 255])
        #expect(wiring.lightsHold(docs: docs, status: status)! == ("G25", false))
        #expect(wiring.presetHold(docs: docs, status: status)! == ("G22", 0))

        let open = PinStatus(revision: 0, closed: 0b0001_0000, claimed: 0b0011_0000, positions: [255, 255])
        #expect(wiring.lightsHold(docs: docs, status: open) == nil)
        #expect(wiring.presetHold(docs: docs, status: open) == nil, "a claimed pin holds nothing")
    }
}

@Suite struct WiringDocsTests {
    @Test func contractExampleDecodes() throws {
        let docs = try WiringDocs(json: WiringFixtures.echoDocs)
        #expect(docs.board == "atom-echo")
        #expect(docs.pins == ["G21", "G25", "G22", "G19", "G23", "G33", "G26", "G32"])
        #expect(docs.analog == ["G32"])
        #expect(docs.led == ["G26", "G32"])
        #expect(docs.claims["G19"] == "speaker")
        #expect(docs.targets.count == 16)
        #expect(docs.targets.contains(.color(.secondary, .value)))
    }

    @Test func skipsUnknownTargets() throws {
        let docs = try WiringDocs(json: #"{"board":"x","pins":["G1"],"analog":["G1"],"led":[],"claims":{},"targets":["brightness","warp"]}"#)
        #expect(docs.targets == [.brightness])
    }

    @Test func rejectsCapabilitiesOfUnlistedPins() {
        #expect(throws: WiringError.unknownPin("G9")) {
            try WiringDocs(json: #"{"board":"x","pins":["G1"],"analog":["G9"],"led":[],"claims":{},"targets":[]}"#)
        }
    }
}

@Suite struct PinStatusTests {
    @Test func contractExampleParsesAgainstEchoDocs() throws {
        let docs = try WiringDocs(json: WiringFixtures.echoDocs)
        let status = try PinStatus(hex: "07013c9e")
        #expect(status.revision == 7)
        #expect(status.hex == "07013c9e")
        #expect(status.state(of: "G21", in: docs) == PinState(closed: true, claimed: false, position: nil))
        for pin in ["G19", "G22", "G23", "G33"] {
            #expect(status.state(of: pin, in: docs)?.claimed == true, "\(pin)")
        }
        #expect(status.state(of: "G25", in: docs) == PinState(closed: false, claimed: false, position: nil))
        #expect(status.state(of: "G26", in: docs)?.claimed == false)
        #expect(status.state(of: "G32", in: docs) == PinState(closed: false, claimed: false, position: 158))
        #expect(status.state(of: "G99", in: docs) == nil)
    }

    @Test(arguments: ["", "0701", "07013", "07013c9g", "07 01 3c 9e", String(repeating: "00", count: 21)])
    func malformedFailsToDecode(hex: String) {
        #expect(throws: WiringError.self) { try PinStatus(hex: hex) }
    }
}
