import Foundation

/// Turns a core's noisy advertisement RSSI into 0-3 signal bars that hold
/// still: readings are averaged, and the bars only move once the average
/// clears a threshold by `hysteresis` dB.
public struct SignalMeter: Equatable, Sendable {
    /// The lowest average RSSI, in dBm, that shows 1, 2 and 3 bars.
    public static let thresholds: [Double] = [-88, -76, -64]
    static let hysteresis = 3.0
    /// The weight of a new reading in the running average.
    static let smoothing = 0.25

    /// 0 (barely in range) to 3 (close by).
    public private(set) var bars: Int
    private var average: Double

    /// Nil for CoreBluetooth's "unavailable" RSSI (127) or any non-negative value.
    public init?(rssi: Int) {
        guard rssi < 0 else { return nil }
        average = Double(rssi)
        bars = Self.bars(at: average)
    }

    /// Folds in a reading; returns whether `bars` changed. Unavailable readings are ignored.
    @discardableResult
    public mutating func add(rssi: Int) -> Bool {
        guard rssi < 0 else { return false }
        average += Self.smoothing * (Double(rssi) - average)
        let old = bars
        let up = Self.bars(at: average - Self.hysteresis)
        let down = Self.bars(at: average + Self.hysteresis)
        if up > bars { bars = up } else if down < bars { bars = down }
        return bars != old
    }

    static func bars(at rssi: Double) -> Int {
        thresholds.filter { rssi >= $0 }.count
    }
}
