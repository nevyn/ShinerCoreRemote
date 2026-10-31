#if DEBUG
import SwiftUI

/// Mock state for the UI playground. Deliberately not a `CoreSession`: the
/// sketches show data the protocol can't deliver yet (every layer at once,
/// per-animation parameter names), so they run on plain values.
@Observable @MainActor final class MockCore {
    var name = "Nevyn's jacket"
    var owner = "Nevyn"
    var lightsOn = true
    var brightness = 180.0
    var preset = 1
    var presetHeldBy: String?
    var layers: [MockLayer] = MockLayer.demoStack
    var selectedLayer = 0
    var ledCount = 144
    var ledOrder = "GRB"
    var maxCurrent = 0
    var mic = true
    var bootPreset = 0
    var mesh = true
    var meshShow = true
    var meshGroup = "kidsville"

    var activeLayers: [Int] { layers.indices.filter { layers[$0].animation != .nothing } }

    /// A stand-in look per preset, so preset chips can preview something.
    static let presetLooks: [[MockLayer]] = [
        [MockLayer(animation: .breathe, color1: .init(1, 0.45, 0.1), color2: .init(0.6, 0, 0.3), speed: 4)],
        MockLayer.demoStack,
        [MockLayer(animation: .scanner, color1: .init(1, 0, 0), speed: 1.5, tau: 4, phi: 3)],
        [MockLayer(animation: .twinkle, color1: .init(0.7, 0.85, 1), color2: .init(1, 0.8, 0.4), speed: 1, tau: 4, phi: 1)],
        [MockLayer(animation: .theaterChase, color1: .init(0, 1, 0.5), speed: 0.8, tau: 4, phi: 2)],
    ]
}

struct MockLayer: Equatable {
    var animation: Anim
    var color1 = RGB(1, 0.16, 0.47)
    var color2 = RGB(0, 0.31, 1)
    var blend = "Add"
    var speed = 2.5
    var beatSync = false
    var tau = 10.0
    var phi = 4.0

    static let empty = MockLayer(animation: .nothing)

    mutating func swapColors() { (color1, color2) = (color2, color1) }

    static var demoStack: [MockLayer] {
        var stack = Array(repeating: empty, count: 10)
        stack[0] = MockLayer(animation: .gradientPulse, speed: 6, tau: 6, phi: 4)
        stack[1] = MockLayer(animation: .comet, color1: .init(1, 1, 1), blend: "Screen", speed: 1.8, tau: 3, phi: 2)
        stack[2] = MockLayer(animation: .sparkle, color1: .init(1, 0.9, 0.6), color2: .init(0, 0, 0), speed: 1, tau: 4, phi: 3)
        return stack
    }
}

/// The firmware's animations (shinercore Animations.cpp), with what tau and
/// phi mean to each, and which colors each one reads.
enum Anim: String, CaseIterable, Identifiable {
    case nothing = "Nothing", staticColor = "Static", opposingWaves = "Opposing Waves",
         singleWave = "Single Wave", breathe = "Breathe", rainbow = "Rainbow", comet = "Comet",
         scanner = "Scanner", twinkle = "Twinkle", theaterChase = "Theater Chase",
         colorWipe = "Color Wipe", gradientPulse = "Gradient Pulse", sparkle = "Sparkle",
         beatPulse = "Beat Pulse"

    var id: String { rawValue }

    var parameters: (tau: String, phi: String)? {
        switch self {
        case .opposingWaves: ("Wave 1 length", "Wave 2 length")
        case .singleWave: ("Wave length", "Phase offset")
        case .rainbow: ("Repeats", "Drift speed")
        case .comet: ("Tail length", "Head width")
        case .scanner: ("Width", "Glow")
        case .twinkle: ("Density", "Twinkle speed")
        case .theaterChase: ("Spacing", "Group size")
        case .colorWipe: ("Wipe speed", "Pause")
        case .gradientPulse: ("Sharpness", "Repeats")
        case .sparkle: ("Flash length", "Density")
        case .nothing, .staticColor, .breathe, .beatPulse: nil
        }
    }

    /// 0, 1 or 2: how many of primary/secondary color the animation reads.
    var colorsUsed: Int {
        switch self {
        case .nothing, .rainbow: 0
        case .staticColor, .singleWave, .comet, .scanner, .theaterChase, .colorWipe, .beatPulse: 1
        case .opposingWaves, .breathe, .twinkle, .gradientPulse, .sparkle: 2
        }
    }

    var symbol: String {
        switch self {
        case .nothing: "circle.dashed"
        case .staticColor: "circle.fill"
        case .opposingWaves: "arrow.left.and.right"
        case .singleWave: "water.waves"
        case .breathe: "lungs"
        case .rainbow: "rainbow"
        case .comet: "moon.stars"
        case .scanner: "arrow.left.arrow.right"
        case .twinkle: "sparkles"
        case .theaterChase: "ellipsis"
        case .colorWipe: "paintbrush"
        case .gradientPulse: "circle.lefthalf.filled"
        case .sparkle: "sparkle"
        case .beatPulse: "waveform"
        }
    }

    /// An approximation of the firmware's pixel function, for previews only.
    func sample(_ i: Int, of n: Int, at time: Double, _ l: MockLayer) -> RGB {
        let t = time / max(l.speed, 0.01)
        let pos = Double(i) / Double(n)
        switch self {
        case .nothing:
            return .black
        case .staticColor:
            return l.color1
        case .opposingWaves:
            return l.color1 * (gamma(curve(t - Double(i) / nz(l.tau))) / 2)
                + l.color2 * (gamma(curve(t + Double(i) / nz(l.phi))) / 2)
        case .singleWave:
            return l.color1 * gamma(curve(t - Double(i) / nz(l.tau) + l.phi))
        case .breathe:
            return l.color1 * gamma(curve(t)) + l.color2 * gamma(curve(t + 0.5))
        case .rainbow:
            return .hue(pos * l.tau / 10 + t * l.phi / 4)
        case .comet:
            let tail = l.tau * 5, head = fract(t) * (Double(n) + tail)
            let d = head - Double(i)
            if d < 0 || d > tail + l.phi { return .black }
            return l.color1 * (d < l.phi ? 1 : pow(1 - (d - l.phi) / tail, 2))
        case .scanner:
            let p = abs(fract(t) * 2 - 1) * Double(n - 1)
            let d = abs(Double(i) - p) - max(1, l.tau) / 2
            return l.color1 * (d <= 0 ? 1 : exp(-d / max(l.phi, 0.1)))
        case .twinkle:
            guard noise(i) < l.tau / 10 else { return .black }
            let v = pow(curve(t * l.phi + noise(i &* 7)), 8)
            return (noise(i &* 13) < 0.5 ? l.color1 : l.color2) * v
        case .theaterChase:
            let spacing = max(2, Int(l.tau)), group = max(1, Int(l.phi))
            let offset = Int(floor(t * Double(spacing)))
            return (i + offset) % spacing < group ? l.color1 : .black
        case .colorWipe:
            let p = fract(t) * 2
            return p < 1 ? (pos < p ? l.color1 : .black) : (pos < p - 1 ? .black : l.color1)
        case .gradientPulse:
            let s = 0.5 + 0.5 * sin(2 * .pi * (pos * l.phi / 4 + t))
            let k = 1 + l.tau / 10 * 4
            let m = 1 / (1 + exp(-(s - 0.5) * 4 * k))
            return l.color1 * m + l.color2 * (1 - m)
        case .sparkle:
            let slot = Int(floor(time * 10 / max(l.tau / 4, 0.25)))
            return noise(i &* 31 &+ slot &* 977) < l.phi / 20 ? l.color1 : l.color2 * 0.08
        case .beatPulse:
            return l.color1 * exp(-fract(time * 2) * 6)
        }
    }
}

struct RGB: Equatable {
    var r, g, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { (self.r, self.g, self.b) = (r, g, b) }
    static let black = RGB(0, 0, 0)

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
    var clamped: RGB { RGB(min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1)) }

    static func + (a: RGB, b: RGB) -> RGB { RGB(a.r + b.r, a.g + b.g, a.b + b.b) }
    static func * (a: RGB, k: Double) -> RGB { RGB(a.r * k, a.g * k, a.b * k) }

    static func hue(_ h: Double) -> RGB {
        let h = fract(h) * 6
        let x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
        return switch Int(h) {
        case 0: RGB(1, x, 0)
        case 1: RGB(x, 1, 0)
        case 2: RGB(0, 1, x)
        case 3: RGB(0, x, 1)
        case 4: RGB(x, 0, 1)
        default: RGB(1, 0, x)
        }
    }

    func blended(over base: RGB, mode: String) -> RGB {
        switch mode {
        case "Set": self
        case "Multiply": RGB(base.r * r, base.g * g, base.b * b)
        case "Average": (base + self) * 0.5
        case "Subtract": RGB(base.r - r, base.g - g, base.b - b)
        case "Screen": RGB(1 - (1 - base.r) * (1 - r), 1 - (1 - base.g) * (1 - g), 1 - (1 - base.b) * (1 - b))
        default: base + self
        }
    }
}

extension RGB {
    init(_ color: Color) {
        let cg = color.resolve(in: EnvironmentValues()).cgColor
        let srgb = cg.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
        let c = srgb?.components ?? [0, 0, 0]
        self.init(Double(c[0]), Double(c[1]), Double(c[2]))
    }
}

private func fract(_ x: Double) -> Double { x - floor(x) }
private func nz(_ x: Double) -> Double { abs(x) < 0.01 ? 0.01 : x }
private func curve(_ x: Double) -> Double { 0.5 - 0.5 * cos(2 * .pi * x) }
private func gamma(_ x: Double) -> Double { pow(x, 2.2) }
private func noise(_ x: Int) -> Double {
    var h = UInt32(truncatingIfNeeded: x) &* 2_654_435_761
    h ^= h >> 13
    h = h &* 0x5bd1_e995
    h ^= h >> 15
    return Double(h) / Double(UInt32.max)
}
#endif
