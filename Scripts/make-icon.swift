#!/usr/bin/env swift
// Draws the app icon (a hexagonal LED board mid-animation, magenta fading to red) into the
// asset catalog's AppIcon set: the iOS icon with its dark and tinted variants, and every Mac size.
// Drawn in the style of the ShinerCore Flasher's icon (shinercore flasher/scripts/make-icon.swift).
// Usage: swift Scripts/make-icon.swift
import AppKit

let iconSet = URL(fileURLWithPath: "ShinerCoreRemote/Assets.xcassets/AppIcon.appiconset")
guard FileManager.default.fileExists(atPath: iconSet.path) else {
    FileHandle.standardError.write(Data("run from the repository root; \(iconSet.path) not found\n".utf8))
    exit(66)
}

typealias RGB = (r: Double, g: Double, b: Double)
func color(_ c: RGB, _ a: Double = 1) -> CGColor { CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: a) }
func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB { (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t) }
func gray(_ c: RGB) -> RGB { let l = 0.3 * c.r + 0.59 * c.g + 0.11 * c.b; return (l, l, l) }

let top: RGB = (0.82, 0.22, 0.92)    // the app's accent
let bottom: RGB = (1, 0.27, 0.16)
let ground: RGB = (0.05, 0.03, 0.07)

enum Style { case standard, dark, tinted }
enum Shape { case iosSquare, macTile }

/// The physical board's rows, top to bottom; small sizes get a coarser board so the dots stay dots.
func rows(pixels: Int) -> [Int] { pixels <= 32 ? [2, 3, 2] : pixels <= 64 ? [3, 4, 5, 4, 3] : [4, 5, 6, 7, 6, 5, 4] }

func draw(_ ctx: CGContext, pixels: Int, style: Style, shape: Shape) {
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    // macOS draws its own icons' shape: an 824-point tile on the 1024 canvas. iOS rounds a full-bleed square.
    let tile = shape == .macTile ? canvas.insetBy(dx: 100, dy: 100) : canvas
    let tilePath = shape == .macTile ? CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil) : CGPath(rect: tile, transform: nil)
    let center = CGPoint(x: 512, y: 512)
    let scale = tile.width / 1024

    if style != .dark {  // iOS supplies the dark variant's background itself
        ctx.saveGState()
        if shape == .macTile { ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color((0, 0, 0), 0.35)) }
        ctx.addPath(tilePath)
        ctx.setFillColor(color(style == .tinted ? (0, 0, 0) : ground))
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    if style == .standard {
        let glow = CGGradient(colorsSpace: nil, colors: [color((0.20, 0.07, 0.24)), color((0.04, 0.02, 0.06))] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 640 * scale, options: [])
    }

    let rowCounts = rows(pixels: pixels)
    let widest = CGFloat(rowCounts.max()!)
    let pitch = 780 * scale / widest
    let rowStep = pitch * 0.87
    let dot = pitch * (pixels <= 64 ? 0.36 : 0.31)

    // The board: a pointy-ended hexagon just around the LEDs, a shade lighter than the ground.
    if style != .tinted {
        let halfWidth = (widest - 1) / 2 * pitch + pitch * 0.62
        let halfHeight = CGFloat(rowCounts.count - 1) / 2 * rowStep + pitch * 0.62
        let inset = halfHeight * 0.58
        let board = CGMutablePath()
        board.move(to: CGPoint(x: center.x - halfWidth, y: center.y))
        board.addLine(to: CGPoint(x: center.x - halfWidth + inset, y: center.y + halfHeight))
        board.addLine(to: CGPoint(x: center.x + halfWidth - inset, y: center.y + halfHeight))
        board.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y))
        board.addLine(to: CGPoint(x: center.x + halfWidth - inset, y: center.y - halfHeight))
        board.addLine(to: CGPoint(x: center.x - halfWidth + inset, y: center.y - halfHeight))
        board.closeSubpath()
        ctx.addPath(board)
        ctx.setFillColor(color((0.17, 0.09, 0.20), style == .dark ? 0.9 : 1))
        ctx.fillPath()
    }

    for (row, count) in rowCounts.enumerated() {
        let y = center.y + (CGFloat(rowCounts.count - 1) / 2 - CGFloat(row)) * rowStep
        let t = Double(row) / Double(max(rowCounts.count - 1, 1))
        for k in 0..<count {
            let x = center.x + (CGFloat(k) - CGFloat(count - 1) / 2) * pitch
            // A brightness wave sweeping diagonally: a frame of an animation, not a static pattern.
            let phase = Double(x - center.x + (y - center.y)) / Double(pitch) * 0.55
            let level = pixels <= 32 ? 1 : 0.3 + 0.7 * pow(0.5 + 0.5 * cos(phase), 1.4)
            var hue = mix(top, bottom, t)
            if style == .tinted { hue = gray(hue) }
            led(ctx, CGPoint(x: x, y: y), dot, hue, level, glow: pixels > 32)
        }
    }
    ctx.restoreGState()
}

func led(_ ctx: CGContext, _ p: CGPoint, _ radius: CGFloat, _ hue: RGB, _ level: Double, glow: Bool) {
    if glow {
        let halo = CGGradient(colorsSpace: nil, colors: [color(hue, 0.55 * level), color(hue, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(halo, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius * 3.2, options: [])
    }
    func lift(_ a: Double, _ b: Double) -> Double { a + (b - a) * level }
    let hot: RGB = (lift(hue.r * 0.6, 1), lift(hue.g * 0.6, 0.94), lift(hue.b * 0.6, 1))
    let rim: RGB = (hue.r * lift(0.3, 1), hue.g * lift(0.3, 1), hue.b * lift(0.3, 1))
    let core = CGGradient(colorsSpace: nil, colors: [color(hot), color(rim)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
    ctx.clip()
    ctx.drawRadialGradient(core, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
    ctx.restoreGState()
}

func write(_ name: String, pixels: Int, style: Style, shape: Shape) {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    draw(ctx, pixels: pixels, style: style, shape: shape)
    let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    do { try png.write(to: iconSet.appendingPathComponent(name)) } catch {
        FileHandle.standardError.write(Data("writing \(name): \(error)\n".utf8)); exit(73)
    }
}

write("AppIcon.png", pixels: 1024, style: .standard, shape: .iosSquare)
write("AppIcon-dark.png", pixels: 1024, style: .dark, shape: .iosSquare)
write("AppIcon-tinted.png", pixels: 1024, style: .tinted, shape: .iosSquare)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        write("mac-\(points)@\(scale)x.png", pixels: points * scale, style: .standard, shape: .macTile)
    }
}
