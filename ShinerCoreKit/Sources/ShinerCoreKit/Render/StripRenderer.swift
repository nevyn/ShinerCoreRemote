import Foundation
import ShinerRender

/// The firmware's render library (ShinerRender.h), addressed by name rather than index,
/// so that a core running other firmware still previews correctly where names match.
public enum RenderLibrary {
    /// The library's animation names, in table order.
    public static let animationNames: [String] = (0 ..< shiner_animation_count()).map {
        String(cString: shiner_animation_name($0))
    }
    /// The library's blend mode names, in table order.
    public static let blendModeNames: [String] = (0 ..< shiner_blend_mode_count()).map {
        String(cString: shiner_blend_mode_name($0))
    }

    /// The library's own docs for the named animation; nil for a name it doesn't know.
    public static func animationDoc(named name: String) -> AnimationDoc? {
        guard let index = animationNames.firstIndex(of: name).map(Int32.init) else { return nil }
        return AnimationDoc(colors: Int(shiner_animation_colors(index)),
                            tau: shiner_animation_parameter(index, 0).map { String(cString: $0) },
                            phi: shiner_animation_parameter(index, 1).map { String(cString: $0) })
    }
}

/// An 8-bit RGB pixel, as on the strip.
public struct PixelColor: Equatable, Sendable {
    public var r, g, b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Parses the wire format of `color` and `color2`: "R G B", 0-255 each.
    public init?(wire: String) {
        let parts = wire.split(separator: " ").compactMap { UInt8($0) }
        guard parts.count == 3 else { return nil }
        self.init(r: parts[0], g: parts[1], b: parts[2])
    }

    public static let black = PixelColor(r: 0, g: 0, b: 0)
}

/// One layer's settings, as the strip preview needs them.
public struct LayerLook: Equatable, Sendable {
    public var animation: String
    public var blendMode: String
    public var color1: PixelColor
    public var color2: PixelColor
    /// Seconds per cycle, or beats per cycle while beat-synced.
    public var speed: Double
    public var beatSynced: Bool
    public var tau: Double
    public var phi: Double

    public init(animation: String, blendMode: String = "Add", color1: PixelColor, color2: PixelColor,
                speed: Double, beatSynced: Bool = false, tau: Double, phi: Double) {
        self.animation = animation
        self.blendMode = blendMode
        self.color1 = color1
        self.color2 = color2
        self.speed = speed
        self.beatSynced = beatSynced
        self.tau = tau
        self.phi = phi
    }

    /// How long one cycle takes in the preview; a beat-synced layer plays at 120 bpm.
    public var secondsPerCycle: Double {
        max(speed, 0.001) * (beatSynced ? StripRenderer.secondsPerBeat : 1)
    }
}

public extension CoreState {
    /// The selected layer's look; nil until its animation is known.
    var layerLook: LayerLook? {
        guard let animation = self[CoreProps.animation] else { return nil }
        return LayerLook(
            animation: animation,
            blendMode: self[CoreProps.blendMode] ?? "Add",
            color1: rawValue(of: CoreProps.color).flatMap(PixelColor.init(wire:)) ?? .black,
            color2: rawValue(of: CoreProps.color2).flatMap(PixelColor.init(wire:)) ?? .black,
            speed: self[CoreProps.speed] ?? 1,
            beatSynced: (self[CoreProps.beatSync] ?? 0) > 0,
            tau: self[CoreProps.tau] ?? 1,
            phi: self[CoreProps.phi] ?? 1)
    }
}

/// Draws layers with the render library, the way one firmware frame does (before global
/// brightness and the power cap). Beat-synced layers and Beat Pulse play against a steady
/// 120 bpm beat, since the app hears no music.
public enum StripRenderer {
    static let secondsPerBeat = 0.5
    /// The firmware's BeatDetector envelope decay time.
    static let envelopeDecay = 0.15

    /// Composites `looks` bottom-up onto black at `seconds` into `pixelCount` pixels.
    /// Nil when the render library doesn't know an animation, because a wrong preview
    /// is worse than none. An unknown blend mode blends as Add, as on the device.
    public static func render(_ looks: [LayerLook], seconds: Double, pixelCount: Int) -> [PixelColor]? {
        var layers: [ShinerLayer] = []
        for look in looks {
            guard let animation = RenderLibrary.animationNames.firstIndex(of: look.animation) else { return nil }
            let blend = RenderLibrary.blendModeNames.firstIndex(of: look.blendMode) ?? 0
            layers.append(ShinerLayer(
                animation: Int32(animation), blendMode: Int32(blend),
                color1: look.color1.shiner, color2: look.color2.shiner,
                tau: Float(look.tau), phi: Float(look.phi),
                time: seconds / look.secondsPerCycle, gain: 1))
        }
        guard pixelCount > 0 else { return [] }
        var pixels = [ShinerRGB](repeating: ShinerRGB(r: 0, g: 0, b: 0), count: pixelCount)
        shiner_render(layers, Int32(layers.count), beatEnvelope(at: seconds), &pixels, Int32(pixelCount))
        return pixels.map { PixelColor(r: $0.r, g: $0.g, b: $0.b) }
    }

    /// 1 on each 120 bpm beat, decaying like the firmware's BeatDetector envelope.
    static func beatEnvelope(at seconds: Double) -> Float {
        let sinceBeat = seconds.truncatingRemainder(dividingBy: secondsPerBeat)
        return Float(exp(-(sinceBeat < 0 ? sinceBeat + secondsPerBeat : sinceBeat) / envelopeDecay))
    }
}

private extension PixelColor {
    var shiner: ShinerRGB { ShinerRGB(r: r, g: g, b: b) }
}
