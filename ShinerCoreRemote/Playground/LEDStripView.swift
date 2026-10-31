#if DEBUG
import SwiftUI

/// A simulated LED strip: the layers composited the way the firmware does,
/// drawn as glowing dots.
struct LEDStripView: View {
    var layers: [MockLayer]
    var count = 48
    var brightness = 1.0
    var glow = true

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let pixels = (0..<count).map { pixel($0, at: t) }
                let pitch = size.width / CGFloat(count)
                let dot = min(pitch * 0.62, size.height * 0.8)
                let y = size.height / 2
                if glow {
                    // Additive radial halos rather than a blur filter, which Canvas clips to a hard-edged box.
                    gc.drawLayer { g in
                        g.blendMode = .plusLighter
                        let r = min(pitch * 2.5, size.height / 2)
                        for (i, p) in pixels.enumerated() {
                            let center = CGPoint(x: (CGFloat(i) + 0.5) * pitch, y: y)
                            let rect = CGRect(x: center.x - r, y: y - r, width: r * 2, height: r * 2)
                            g.fill(Path(ellipseIn: rect), with: .radialGradient(
                                Gradient(colors: [0.22, 0.09, 0.025, 0].map { p.color.opacity($0) }),
                                center: center, startRadius: 0, endRadius: r))
                        }
                    }
                }
                for (i, p) in pixels.enumerated() {
                    let rect = CGRect(x: (CGFloat(i) + 0.5) * pitch - dot / 2, y: y - dot / 2, width: dot, height: dot)
                    gc.fill(Path(ellipseIn: rect), with: .color(Color(white: 0.16)))
                    gc.fill(Path(ellipseIn: rect), with: .color(p.color))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func pixel(_ i: Int, at t: Double) -> RGB {
        var out = RGB.black
        for layer in layers where layer.animation != .nothing {
            out = layer.animation.sample(i, of: count, at: t, layer).blended(over: out, mode: layer.blend).clamped
        }
        return out * brightness
    }
}

#Preview {
    VStack(spacing: 24) {
        ForEach(Anim.allCases) { anim in
            VStack(alignment: .leading) {
                Text(anim.rawValue).font(.caption).foregroundStyle(.secondary)
                LEDStripView(layers: [MockLayer(animation: anim, tau: 6, phi: 3)]).frame(height: 14)
            }
        }
    }
    .padding()
    .background(.black)
}
#endif
