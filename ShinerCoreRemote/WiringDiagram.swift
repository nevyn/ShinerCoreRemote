import SwiftUI

/// Board geometry as seen from the back, Grove socket facing down, with pin
/// labels as printed on the case. App-owned and keyed by the firmware's board
/// id; checked against the real hardware.
struct BoardLayout {
    /// The firmware's board id ("atom-lite").
    let id: String
    let name: String
    let leftHeader: [String]   // top to bottom
    let rightHeader: [String]
    let grove: [String]        // black, red, yellow, white
    static let groveColors: [Color] = [.black, .red, .yellow, .white]
    static let groveColorNames = ["black", "red", "yellow", "white"]

    static let atomLite = BoardLayout(
        id: "atom-lite",
        name: "Atom Lite",
        leftHeader: ["3V3", "G22", "G19", "G23", "G33"],
        rightHeader: ["G21", "G25", "5V", "G"],
        grove: ["G", "5V", "G26", "G32"])
    static let atomEcho = BoardLayout(
        id: "atom-echo",
        name: "Atom Echo",
        leftHeader: ["3V3", "G22", "G19", "G23", "G33"],
        rightHeader: ["G21", "G25", "5V", "G"],
        grove: ["G", "5V", "G26", "G32"])
    static let atomS3Lite = BoardLayout(
        id: "atoms3-lite",
        name: "AtomS3 Lite",
        leftHeader: ["3V3", "G5", "G6", "G7", "G8"],
        rightHeader: ["G39", "G38", "5V", "G"],
        grove: ["G", "5V", "G2", "G1"])

    /// Every board this app has a drawing of, in the order the build guide lists them.
    static let all = [atomLite, atomEcho, atomS3Lite]

    /// Nil for a board this app has no drawing of.
    init?(board id: String) {
        guard let layout = Self.all.first(where: { $0.id == id }) else { return nil }
        self = layout
    }

    private init(id: String, name: String, leftHeader: [String], rightHeader: [String], grove: [String]) {
        self.id = id
        self.name = name
        self.leftHeader = leftHeader
        self.rightHeader = rightHeader
        self.grove = grove
    }

    func isGroveSignal(_ label: String) -> Bool { grove.dropFirst(2).contains(label) }

    /// The yellow Grove wire's pin, which drives LEDs in every board's default wiring:
    /// the build guide solders the strip's DIN to it.
    var ledPin: String { grove[2] }

    func location(of label: String, grove onGrove: Bool) -> String {
        if onGrove, let i = grove.firstIndex(of: label) {
            let wire = "the \(Self.groveColorNames[i]) wire of the Grove cable"
            return isGroveSignal(label) ? "\(wire) (\(label))" : wire
        }
        return label == "G" ? "G (ground) on the back header" : "\(label) on the back header"
    }
}

struct BoardGeometry {
    let board: BoardLayout
    let origin: CGPoint
    let size: CGFloat = 140
    var rect: CGRect { CGRect(origin: origin, size: CGSize(width: size, height: size)) }

    func hole(_ label: String) -> (point: CGPoint, outward: CGFloat)? {
        if let i = board.leftHeader.firstIndex(of: label) {
            return (CGPoint(x: origin.x + 12, y: origin.y + 30 + CGFloat(i) * 20), -1)
        }
        if let i = board.rightHeader.firstIndex(of: label) {
            return (CGPoint(x: origin.x + size - 12, y: origin.y + 30 + CGFloat(i) * 20), 1)
        }
        return nil
    }

    func groveX(_ i: Int) -> CGFloat { origin.x + 40 + CGFloat(i) * 20 }
    var groveY: CGFloat { origin.y + size + 4 }
}

private func roundedPolyline(_ pts: [CGPoint], radius: CGFloat = 8) -> Path {
    var p = Path()
    guard let first = pts.first, let last = pts.last else { return p }
    p.move(to: first)
    if pts.count > 2 {
        for i in 1 ..< pts.count - 1 {
            p.addArc(tangent1End: pts[i], tangent2End: pts[i + 1], radius: radius)
        }
    }
    p.addLine(to: last)
    return p
}

private func strokeWire(_ ctx: GraphicsContext, _ path: Path, _ color: Color, faded: Bool = false) {
    var c = ctx
    if faded { c.opacity = 0.3 }
    let outline: Color = color == .black ? Color(white: 0.55) : .black.opacity(0.6)
    c.stroke(path, with: .color(outline), style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
    c.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
}

private func label(_ s: String, bold: Bool = false, color: Color = .primary, size: CGFloat = 9) -> Text {
    Text(s).font(.system(size: size, weight: bold ? .bold : .regular, design: .monospaced)).foregroundColor(color)
}

/// Print on the case, which is light in both appearances.
private let boardInk = Color(white: 0.4)

/// Draws the board seen from the back: headers left and right, the Grove socket at the bottom.
private func drawBoard(_ ctx: GraphicsContext, _ g: BoardGeometry, emphasis: [String: Color], groveTint: Color? = nil) {
    let body = Path(roundedRect: g.rect, cornerRadius: 18)
    ctx.fill(body, with: .color(Color(white: 0.92)))
    ctx.stroke(body, with: .color(Color(white: 0.6)), lineWidth: 1)
    let center = CGPoint(x: g.rect.midX, y: g.rect.midY - 6)
    ctx.draw(label("ATOM", bold: true, color: .gray, size: 13), at: center)
    ctx.draw(label(g.board.name, color: .gray, size: 8), at: CGPoint(x: center.x, y: center.y + 14))

    for (header, x) in [(g.board.leftHeader, g.origin.x + 12), (g.board.rightHeader, g.origin.x + g.size - 12)] {
        let strip = CGRect(x: x - 7, y: g.origin.y + 20, width: 14, height: CGFloat(header.count) * 20)
        ctx.fill(Path(roundedRect: strip, cornerRadius: 3), with: .color(.black))
        for name in header {
            guard let (p, out) = g.hole(name) else { continue }
            let hole = CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
            ctx.fill(Path(hole), with: .color(Color(white: 0.35)))
            let tint = emphasis[name]
            if let tint {
                ctx.stroke(Path(ellipseIn: hole.insetBy(dx: -3, dy: -3)), with: .color(tint), lineWidth: 2)
            }
            ctx.draw(label(name, bold: tint != nil, color: tint ?? boardInk),
                     at: CGPoint(x: p.x - out * 12, y: p.y), anchor: out < 0 ? .leading : .trailing)
        }
    }

    let socket = CGRect(x: g.groveX(0) - 10, y: g.rect.maxY - 12, width: 80, height: 16)
    ctx.fill(Path(roundedRect: socket, cornerRadius: 2), with: .color(.white))
    ctx.stroke(Path(roundedRect: socket, cornerRadius: 2), with: .color(.gray), lineWidth: 1)
    if let groveTint {
        ctx.stroke(Path(roundedRect: socket.insetBy(dx: -4, dy: -4), cornerRadius: 5), with: .color(groveTint), lineWidth: 2.5)
    }
    ctx.draw(label("Grove", bold: groveTint != nil, color: groveTint ?? boardInk, size: groveTint == nil ? 8 : 10),
             at: CGPoint(x: socket.midX, y: socket.minY - (groveTint == nil ? 8 : 12)))
}

struct BoardFaceView: View {
    let board: BoardLayout
    /// Pins drawn bold in their color: header holes get a ring, Grove signal wires stay unfaded.
    let emphasis: [String: Color]
    /// Outlines the Grove socket in this color.
    var groveTint: Color?

    var body: some View {
        Canvas { ctx, size in
            let g = BoardGeometry(board: board, origin: CGPoint(x: (size.width - 140) / 2, y: 8))
            for (i, name) in board.grove.enumerated() {
                let x = g.groveX(i)
                let path = roundedPolyline([CGPoint(x: x, y: g.groveY - 4), CGPoint(x: x, y: g.groveY + 30)])
                let signal = board.isGroveSignal(name)
                strokeWire(ctx, path, BoardLayout.groveColors[i], faded: signal && emphasis[name] == nil)
                let tint = signal ? emphasis[name] : nil
                ctx.draw(label(name, bold: tint != nil, color: tint ?? .secondary, size: 8),
                         at: CGPoint(x: x, y: g.groveY + 40))
            }
            drawBoard(ctx, g, emphasis: emphasis.filter { !board.isGroveSignal($0.key) }, groveTint: groveTint)
        }
    }
}

/// One wire from a board pin to a component leg.
private struct Wire {
    let from: String
    let grove: Bool
    let leg: Int
    let legName: String
}

private func wires(for kind: RoleKind, pin: String, on board: BoardLayout?) -> [Wire] {
    let pinOnGrove = board?.isGroveSignal(pin) ?? false
    switch kind {
    case .knob:
        return [Wire(from: "G", grove: false, leg: 0, legName: "One outer leg"),
                Wire(from: pin, grove: pinOnGrove, leg: 1, legName: "Middle leg"),
                Wire(from: "3V3", grove: false, leg: 2, legName: "Other outer leg")]
    case .switch, .button:
        return [Wire(from: pin, grove: pinOnGrove, leg: 0, legName: "One leg"),
                Wire(from: "G", grove: false, leg: 1, legName: "Other leg")]
    case .leds:
        return [Wire(from: "G", grove: true, leg: 0, legName: "The strip's G (or GND)"),
                Wire(from: pin, grove: true, leg: 1, legName: "The strip's DIN"),
                Wire(from: "5V", grove: true, leg: 2, legName: "The strip's 5V")]
    case .nothing:
        return []
    }
}

struct WiringDiagramView: View {
    let board: BoardLayout
    let pin: String
    let kind: RoleKind
    var contextLED: String? = nil

    var body: some View {
        Canvas { ctx, size in
            let g = BoardGeometry(board: board, origin: CGPoint(x: (size.width - 140) / 2 - 20, y: 14))
            let ws = wires(for: kind, pin: pin, on: board)
            let legTipY: CGFloat = 268
            let cx = size.width - 80
            let legXs: [CGFloat] = kind == .switch || kind == .button ? [cx - 14, cx + 14] : [cx - 24, cx, cx + 24]
            var groveUsed = Set(ws.filter(\.grove).map(\.from))

            // An already-wired LED strip, faded, so the new wires have something to orient by.
            if kind != .leds, let led = contextLED, let di = board.grove.firstIndex(of: led) {
                let stripPads: [CGFloat] = [40, 60, 80]
                for (n, gi) in [0, 1, di].enumerated() {
                    let x = g.groveX(gi)
                    let laneY = g.groveY + 18 + CGFloat(n) * 7
                    strokeWire(ctx, roundedPolyline([
                        CGPoint(x: x, y: g.groveY - 4), CGPoint(x: x, y: laneY),
                        CGPoint(x: stripPads[n], y: laneY), CGPoint(x: stripPads[n], y: 300),
                    ]), BoardLayout.groveColors[gi], faded: true)
                    groveUsed.insert(board.grove[gi])
                }
                let strip = CGRect(x: 28, y: 300, width: 64, height: 18)
                ctx.fill(Path(roundedRect: strip, cornerRadius: 3), with: .color(Color(white: 0.85)))
                ctx.draw(label("LED strip", color: .secondary, size: 8), at: CGPoint(x: strip.midX, y: strip.midY))
            }
            for (gi, name) in board.grove.enumerated() where !groveUsed.contains(name) {
                let x = g.groveX(gi)
                strokeWire(ctx, roundedPolyline([CGPoint(x: x, y: g.groveY - 4), CGPoint(x: x, y: g.groveY + 14)]),
                           BoardLayout.groveColors[gi], faded: true)
            }

            var used: [String: Color] = [:]
            for (n, w) in ws.enumerated() {
                let legTip = CGPoint(x: legXs[w.leg], y: legTipY)
                let laneY = legTipY - 22 - CGFloat(n) * 9
                var pts: [CGPoint]
                var color: Color
                if w.grove, let gi = board.grove.firstIndex(of: w.from) {
                    let x = g.groveX(gi)
                    pts = [CGPoint(x: x, y: g.groveY - 4), CGPoint(x: x, y: laneY), CGPoint(x: legTip.x, y: laneY), legTip]
                    color = BoardLayout.groveColors[gi]
                } else if let (p, out) = g.hole(w.from) {
                    let outX = out < 0 ? g.rect.minX - 14 - CGFloat(n) * 8 : g.rect.maxX + 14 + CGFloat(n) * 8
                    pts = [p, CGPoint(x: outX, y: p.y), CGPoint(x: outX, y: laneY), CGPoint(x: legTip.x, y: laneY), legTip]
                    color = w.from == "3V3" ? .orange : w.from == "G" ? Color(white: 0.2) : .green
                    used[w.from] = color
                } else { continue }
                strokeWire(ctx, roundedPolyline(pts), color)
            }
            drawBoard(ctx, g, emphasis: used)

            switch kind {
            case .knob: drawPot(ctx, cx: cx, legTipY: legTipY, legXs: legXs)
            case .switch: drawSwitch(ctx, cx: cx, legTipY: legTipY, legXs: legXs)
            case .button: drawButton(ctx, cx: cx, legTipY: legTipY, legXs: legXs)
            case .leds: drawStrip(ctx, cx: cx, legTipY: legTipY, legXs: legXs)
            case .nothing: break
            }
        }
    }

    private func drawLegs(_ ctx: GraphicsContext, _ legXs: [CGFloat], _ tipY: CGFloat) {
        for x in legXs {
            ctx.fill(Path(CGRect(x: x - 3, y: tipY, width: 6, height: 22)), with: .color(Color(white: 0.7)))
            ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: tipY - 4, width: 8, height: 8)), with: .color(Color(white: 0.8)))
        }
    }

    private func drawPot(_ ctx: GraphicsContext, cx: CGFloat, legTipY: CGFloat, legXs: [CGFloat]) {
        drawLegs(ctx, legXs, legTipY)
        let body = CGRect(x: cx - 40, y: legTipY + 22, width: 80, height: 50)
        ctx.fill(Path(roundedRect: body, cornerRadius: 6), with: .color(Color(white: 0.3)))
        let c = CGPoint(x: cx, y: body.midY)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 18, y: c.y - 18, width: 36, height: 36)), with: .color(Color(white: 0.7)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 13, y: c.y - 13, width: 26, height: 26)), with: .color(Color(white: 0.85)))
        var tick = Path()
        tick.move(to: c)
        tick.addLine(to: CGPoint(x: c.x + 9, y: c.y - 9))
        ctx.stroke(tick, with: .color(.black), lineWidth: 2)
    }

    private func drawSwitch(_ ctx: GraphicsContext, cx: CGFloat, legTipY: CGFloat, legXs: [CGFloat]) {
        drawLegs(ctx, legXs, legTipY)
        let body = CGRect(x: cx - 32, y: legTipY + 22, width: 64, height: 34)
        var lever = Path(roundedRect: CGRect(x: cx - 4, y: body.maxY - 4, width: 8, height: 26), cornerRadius: 4)
        lever = lever.applying(CGAffineTransform(translationX: cx, y: body.maxY).rotated(by: -0.4).translatedBy(x: -cx, y: -body.maxY))
        ctx.fill(lever, with: .color(Color(white: 0.75)))
        ctx.fill(Path(roundedRect: body, cornerRadius: 5), with: .color(Color(white: 0.25)))
    }

    private func drawButton(_ ctx: GraphicsContext, cx: CGFloat, legTipY: CGFloat, legXs: [CGFloat]) {
        drawLegs(ctx, legXs, legTipY)
        let body = CGRect(x: cx - 24, y: legTipY + 22, width: 48, height: 44)
        ctx.fill(Path(roundedRect: body, cornerRadius: 4), with: .color(Color(white: 0.25)))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 14, y: body.midY - 14, width: 28, height: 28)), with: .color(.red))
    }

    private func drawStrip(_ ctx: GraphicsContext, cx: CGFloat, legTipY: CGFloat, legXs: [CGFloat]) {
        let body = CGRect(x: cx - 46, y: legTipY + 8, width: 92, height: 50)
        ctx.fill(Path(roundedRect: body, cornerRadius: 3), with: .color(Color(white: 0.97)))
        ctx.stroke(Path(roundedRect: body, cornerRadius: 3), with: .color(.gray), lineWidth: 1)
        for i in 0 ..< 3 {
            let led = CGRect(x: body.minX + 10 + CGFloat(i) * 30, y: body.midY + 2, width: 14, height: 14)
            ctx.fill(Path(roundedRect: led, cornerRadius: 2), with: .color(Color(white: 0.9)))
            ctx.stroke(Path(roundedRect: led, cornerRadius: 2), with: .color(Color(white: 0.6)), lineWidth: 1)
        }
        ctx.draw(label("→ → →", bold: true, color: .pink, size: 10), at: CGPoint(x: body.midX, y: body.maxY + 10))
        for (x, name) in zip(legXs, ["G", "DIN", "5V"]) {
            ctx.fill(Path(roundedRect: CGRect(x: x - 7, y: legTipY - 2, width: 14, height: 10), cornerRadius: 2),
                     with: .color(copper))
            ctx.draw(label(name, size: 7), at: CGPoint(x: x, y: legTipY + 16))
        }
    }

}

/// A Grove cable cut in half, the halves' ends bared to the copper.
struct GroveCableCutView: View {
    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2 + 8
            let cutX = size.width / 2
            for (side, x) in [(-1.0, 12.0), (1.0, size.width - 48)] {
                let body = CGRect(x: x, y: mid - 22, width: 36, height: 44)
                ctx.fill(Path(roundedRect: body, cornerRadius: 4), with: .color(Color(white: 0.95)))
                ctx.stroke(Path(roundedRect: body, cornerRadius: 4), with: .color(.gray), lineWidth: 1)
                for (i, color) in BoardLayout.groveColors.enumerated() {
                    let y = mid - 13.5 + CGFloat(i) * 9
                    let from = side < 0 ? body.maxX : cutX + 16
                    let to = side < 0 ? cutX - 16 : body.minX
                    let bare = side < 0 ? CGRect(x: to, y: y - 1.5, width: 7, height: 3) : CGRect(x: from - 7, y: y - 1.5, width: 7, height: 3)
                    ctx.fill(Path(roundedRect: bare, cornerRadius: 1.5), with: .color(copper))
                    var wire = Path()
                    wire.move(to: CGPoint(x: from, y: y))
                    wire.addLine(to: CGPoint(x: to, y: y))
                    strokeWire(ctx, wire, color)
                }
            }
            var cut = Path()
            cut.move(to: CGPoint(x: cutX, y: mid - 26))
            cut.addLine(to: CGPoint(x: cutX, y: mid + 26))
            ctx.stroke(cut, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
            ctx.draw(Image(systemName: "scissors"), at: CGPoint(x: cutX, y: mid - 40))
        }
        .foregroundStyle(Color.accentColor)
        .accessibilityElement()
        .accessibilityLabel("A Grove cable cut in the middle")
    }
}

/// The start of an LED strip with the three Grove wires soldered to its pads: red to 5V,
/// yellow to DIN, black to GND, at the end where the printed arrows start.
struct StripSolderView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { ctx, size in
            let dark = colorScheme == .dark
            let mid = size.height / 2 - 4
            let strip = CGRect(x: 100, y: mid - 36, width: size.width - 100 + 8, height: 72)
            ctx.fill(Path(roundedRect: strip, cornerRadius: 4), with: .color(Color(white: dark ? 0.2 : 0.98)))
            ctx.stroke(Path(roundedRect: strip, cornerRadius: 4), with: .color(Color(white: dark ? 0.45 : 0.7)), lineWidth: 1)

            let pads: [(name: String, wire: Color, y: CGFloat)] = [("5V", .red, mid - 21), ("DIN", .yellow, mid), ("GND", .black, mid + 21)]
            let padX = strip.minX + 14
            for pad in pads {
                ctx.fill(Path(roundedRect: CGRect(x: padX - 8, y: pad.y - 6, width: 16, height: 12), cornerRadius: 2), with: .color(copper))
                ctx.draw(label(pad.name, bold: true, size: 11), at: CGPoint(x: padX + 13, y: pad.y), anchor: .leading)
            }
            for (i, pad) in pads.enumerated() {
                let startY = mid + CGFloat(i - 1) * 40
                strokeWire(ctx, roundedPolyline([CGPoint(x: -4, y: startY), CGPoint(x: 40, y: startY),
                                                  CGPoint(x: 70, y: pad.y), CGPoint(x: padX, y: pad.y)]), pad.wire)
                ctx.fill(Path(ellipseIn: CGRect(x: padX - 5, y: pad.y - 5, width: 10, height: 10)), with: .color(Color(white: 0.78)))
            }

            let ledColor = Color(white: dark ? 0.85 : 0.96)
            var x = strip.minX + 104
            while x < size.width {
                let led = CGRect(x: x - 15, y: mid - 15, width: 30, height: 30)
                ctx.fill(Path(roundedRect: led, cornerRadius: 3), with: .color(ledColor))
                ctx.stroke(Path(roundedRect: led, cornerRadius: 3), with: .color(Color(white: 0.6)), lineWidth: 1)
                ctx.stroke(Path(ellipseIn: led.insetBy(dx: 7, dy: 7)), with: .color(Color(white: 0.7)), lineWidth: 1)
                ctx.draw(Image(systemName: "arrow.right"), at: CGPoint(x: x - 36, y: mid))
                x += 72
            }
            ctx.draw(Text("Solder here").font(.footnote.weight(.semibold)).foregroundColor(.accentColor),
                     at: CGPoint(x: padX + 8, y: strip.maxY + 16))
            ctx.draw(Text("Arrows point away from Data In").font(.footnote).foregroundColor(.secondary),
                     at: CGPoint(x: size.width - 4, y: strip.minY - 16), anchor: .trailing)
        }
        .foregroundStyle(.pink)
        .accessibilityElement()
        .accessibilityLabel("The red wire soldered to 5V, yellow to DIN and black to GND, at the end of the strip where the arrows start")
    }
}

private let copper = Color(red: 0.85, green: 0.65, blue: 0.3)

/// Numbered wiring instructions. Without a layout (an unknown board) the
/// steps name bare pin labels.
struct WiringSteps: View {
    let layout: BoardLayout?
    let boardName: String
    let pin: String
    let kind: RoleKind

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(wires(for: kind, pin: pin, on: layout).enumerated()), id: \.offset) { n, w in
                Text("\(n + 1). \(w.legName) → \(layout?.location(of: w.from, grove: w.grove) ?? w.from).")
            }
            switch kind {
            case .knob:
                Label("Use 3V3, never the red 5V wire: more than 3.3 V on \(pin) can damage the \(boardName).",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Turns the wrong way? Swap the outer legs, or tap Reverse below.")
                    .foregroundStyle(.secondary)
            case .leds:
                Text("Connect the end where the strip's arrows point away from the Atom; the other end won't light up.")
                    .foregroundStyle(.secondary)
            default:
                Text("Any \(kind == .button ? "push button" : "on/off switch") works; which leg is which doesn't matter.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }
}

#Preview("Wiring diagrams") {
    ScrollView {
        VStack(spacing: 24) {
            WiringDiagramView(board: .atomEcho, pin: "G32", kind: .knob, contextLED: "G26").frame(height: 340)
            WiringSteps(layout: .atomEcho, boardName: "Atom Echo", pin: "G32", kind: .knob)
            WiringDiagramView(board: .atomEcho, pin: "G26", kind: .leds).frame(height: 340)
            WiringSteps(layout: .atomEcho, boardName: "Atom Echo", pin: "G26", kind: .leds)
            WiringDiagramView(board: .atomS3Lite, pin: "G38", kind: .switch, contextLED: "G2").frame(height: 340)
            WiringSteps(layout: nil, boardName: "atoms3-lite", pin: "G38", kind: .switch)
            BoardFaceView(board: .atomS3Lite, emphasis: ["G2": RoleKind.leds.tint], groveTint: RoleKind.leds.tint).frame(height: 200)
            GroveCableCutView().frame(height: 110)
            StripSolderView().frame(height: 150)
        }
        .padding()
    }
}
