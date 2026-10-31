import SwiftUI
import ShinerCoreKit

/// The strip preview: layers drawn by the firmware's render library as glowing dots, in a
/// black well in both appearances, because additive glow on white is invisible. Under
/// Reduce Motion it shows a still frame a third of the way into the cycle, redrawn when a
/// setting changes. With a `caption`, the well shows the caption instead of dots.
struct StripPreview: View {
    /// Composited bottom first, as `StripRenderer` does.
    let layers: [LayerSummary.Layer]
    /// The core's LED count; strips longer than `dots` are averaged down to fit.
    let pixelCount: Int
    var caption: String?
    /// 0-1, applied to the whole frame.
    var brightness = 1.0
    /// A thin strip of plain dots, for rows and cards.
    var compact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = PreviewClock()

    /// One layer drawn on its own.
    init(looks: [LayerLook], pixelCount: Int, caption: String? = nil, compact: Bool = false) {
        self.init(layers: looks.map { LayerSummary.Layer(index: 0, look: $0) }, pixelCount: pixelCount,
                  caption: caption, compact: compact)
    }

    init(layers: [LayerSummary.Layer], pixelCount: Int, caption: String? = nil, brightness: Double = 1,
         compact: Bool = false, dots: Int? = nil) {
        self.layers = layers
        self.pixelCount = pixelCount
        self.caption = caption
        self.brightness = brightness
        self.compact = compact
        self.dots = dots ?? (compact ? 24 : 72)
    }

    /// At most this many dots; longer strips are binned.
    private let dots: Int

    var body: some View {
        ZStack {
            if let caption {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let pixels = render(at: context.date)
                    Canvas { gc, size in Self.draw(pixels, in: &gc, size: size, glow: !compact) }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 12 : 44, maxHeight: compact ? 12 : .infinity)
        .background(.black, in: .rect(cornerRadius: compact ? 6 : 12))
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }

    private func render(at date: Date) -> [PixelColor] {
        // One layer plays at its own pace, so a speed change alters the pace without a jump;
        // a stack has one pace per layer, so it plays in seconds.
        let secondsPerCycle = layers.count == 1 ? layers[0].look.secondsPerCycle : 1
        let seconds = reduceMotion ? secondsPerCycle / 3 : clock.advance(to: date, secondsPerCycle: secondsPerCycle)
        let pixels = StripRenderer.render(layers, seconds: seconds, pixelCount: max(pixelCount, 1), brightness: brightness) ?? []
        // A thin strip bins by the brightest pixel, so that a lone spark or comet head stays visible.
        return Self.binned(pixels, into: dots, brightest: compact)
    }

    /// Averages runs of pixels, or takes each run's per-channel maximum, so that at most
    /// `count` remain.
    static func binned(_ pixels: [PixelColor], into count: Int, brightest: Bool = false) -> [PixelColor] {
        guard pixels.count > count else { return pixels }
        return (0 ..< count).map { bin in
            let run = pixels[bin * pixels.count / count ..< (bin + 1) * pixels.count / count]
            func reduce(_ channel: KeyPath<PixelColor, UInt8>) -> UInt8 {
                brightest ? run.map { $0[keyPath: channel] }.max()!
                          : UInt8(run.reduce(0) { $0 + Int($1[keyPath: channel]) } / run.count)
            }
            return PixelColor(r: reduce(\.r), g: reduce(\.g), b: reduce(\.b))
        }
    }

    private static func draw(_ pixels: [PixelColor], in gc: inout GraphicsContext, size: CGSize, glow: Bool) {
        guard !pixels.isEmpty else { return }
        let inset: CGFloat = glow ? 8 : 4
        let pitch = (size.width - inset * 2) / CGFloat(pixels.count)
        let dot = min(pitch * 0.62, size.height * 0.5)
        let y = size.height / 2
        let colors = pixels.map { Color(.sRGB, red: Double($0.r) / 255, green: Double($0.g) / 255, blue: Double($0.b) / 255) }
        func center(_ i: Int) -> CGFloat { inset + (CGFloat(i) + 0.5) * pitch }
        // Additive radial halos rather than a blur filter, which Canvas clips to a hard-edged box.
        if glow {
            gc.drawLayer { g in
                g.blendMode = .plusLighter
                let r = min(pitch * 2.5, size.height / 2)
                for (i, color) in colors.enumerated() {
                    let c = CGPoint(x: center(i), y: y)
                    g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: y - r, width: r * 2, height: r * 2)),
                           with: .radialGradient(Gradient(colors: [0.22, 0.09, 0.025, 0].map { color.opacity($0) }),
                                                 center: c, startRadius: 0, endRadius: r))
                }
            }
        }
        for (i, color) in colors.enumerated() {
            let rect = CGRect(x: center(i) - dot / 2, y: y - dot / 2, width: dot, height: dot)
            gc.fill(Path(ellipseIn: rect), with: .color(Color(white: 0.16)))
            gc.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }
}

/// Playback position that advances by the current speed each frame, so that changing the
/// speed changes the pace instead of jumping to another point in the cycle.
@MainActor
final class PreviewClock {
    private var cycles = 0.0
    private var last: Date?

    /// The layer time to render at, in seconds at the current speed.
    func advance(to date: Date, secondsPerCycle: Double) -> Double {
        // A long gap (backgrounded, scrolled away) resumes rather than leaping ahead.
        let dt = last.map { min(max(date.timeIntervalSince($0), 0), 0.1) } ?? 0
        last = date
        cycles += dt / secondsPerCycle
        return cycles * secondsPerCycle
    }
}

#Preview("Animations") {
    let looks = RenderLibrary.animationNames.dropFirst().map {
        LayerLook(animation: $0, color1: PixelColor(r: 255, g: 40, b: 120), color2: PixelColor(r: 0, g: 80, b: 255),
                  speed: 2.5, tau: 6, phi: 3)
    }
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(looks, id: \.animation) { look in
                Text(look.animation).font(.caption).foregroundStyle(.secondary)
                StripPreview(looks: [look], pixelCount: 32)
            }
            Text("Nothing").font(.caption).foregroundStyle(.secondary)
            StripPreview(looks: [], pixelCount: 32, caption: "Layer 3 is empty")
        }
        .padding()
    }
}
