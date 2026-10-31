import Testing
@testable import ShinerCoreKit

struct SignalMeterTests {
    @Test func firstReadingSetsBars() {
        #expect(SignalMeter(rssi: -50)?.bars == 3)
        #expect(SignalMeter(rssi: -70)?.bars == 2)
        #expect(SignalMeter(rssi: -80)?.bars == 1)
        #expect(SignalMeter(rssi: -95)?.bars == 0)
    }

    @Test func unavailableRSSIIsIgnored() {
        #expect(SignalMeter(rssi: 127) == nil)
        var meter = SignalMeter(rssi: -70)!
        let changed = meter.add(rssi: 127)
        #expect(!changed)
        #expect(meter == SignalMeter(rssi: -70)!)
    }

    @Test func noiseAroundAThresholdDoesNotFlicker() {
        var meter = SignalMeter(rssi: -75)!
        #expect(meter.bars == 2)
        var changes = 0
        for rssi in [-78, -73, -79, -74, -77, -72, -78, -75, -79, -73] where meter.add(rssi: rssi) {
            changes += 1
        }
        #expect(changes == 0)
        #expect(meter.bars == 2)
    }

    @Test func sustainedChangeMovesBars() {
        var meter = SignalMeter(rssi: -60)!
        for _ in 0 ..< 20 { meter.add(rssi: -95) }
        #expect(meter.bars == 0)
        for _ in 0 ..< 20 { meter.add(rssi: -50) }
        #expect(meter.bars == 3)
    }
}
