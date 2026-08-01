import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Wire format: "R G B", 0–255 per component.
public struct ColorConverter: PropertyConverter {
    public static func convert(_ raw: String) -> Color? {
        let components = raw.components(separatedBy: " ")
        guard components.count == 3,
              let red = Double(components[0]), (0...255).contains(red),
              let green = Double(components[1]), (0...255).contains(green),
              let blue = Double(components[2]), (0...255).contains(blue)
        else { return nil }
        return Color(red: red / 255, green: green / 255, blue: blue / 255)
    }

    public static func unconvert(_ value: Color) -> String {
        let (red, green, blue, _) = value.rgba
        // Extended-sRGB components from wide-gamut picks can exceed 0...1;
        // the wire format can't.
        func wire(_ component: CGFloat) -> Int {
            Int((min(max(component, 0), 1) * 255).rounded())
        }
        return "\(wire(red)) \(wire(green)) \(wire(blue))"
    }
}

public extension Color {
    #if canImport(UIKit)
    var asNative: UIColor { UIColor(self) }
    #elseif canImport(AppKit)
    var asNative: NSColor { NSColor(self) }
    #endif

    var rgba: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var t = (CGFloat(), CGFloat(), CGFloat(), CGFloat())
        #if canImport(AppKit)
        // getRed raises on non-RGB colors; sRGB conversion is identity for
        // colors made with Color(red:green:blue:), so no round-trip drift.
        let color = asNative.usingColorSpace(.sRGB) ?? .black
        #else
        let color = asNative
        #endif
        color.getRed(&t.0, green: &t.1, blue: &t.2, alpha: &t.3)
        return t
    }
}
