import SwiftUI

/// The build guide: getting started's step 3, connecting an LED strip to a board, one screen per step.
enum BuildGuideStep: Int, CaseIterable, Hashable {
    case board = 1, cable, solder, plugIn, powerUp

    var next: BuildGuideStep? { BuildGuideStep(rawValue: rawValue + 1) }
}

/// One step of the build guide. `board` is the picked board id; every step after `.board` requires one.
/// `next` moves on, or closes onboarding after the last step.
struct BuildGuideStepView: View {
    let step: BuildGuideStep
    @Binding var board: String?
    let next: () -> Void

    var body: some View {
        switch step {
        case .board: pickBoard
        case .cable: cable
        case .solder: solder
        case .plugIn: plugIn
        case .powerUp: powerUp
        }
    }

    private func page(_ title: String, next label: String = "Next", enabled: Bool = true,
                      @ViewBuilder content: () -> some View) -> some View {
        OnboardingPage(title: title, guideStep: step, next: label, nextEnabled: enabled, action: next, content: content)
    }

    private var layout: BoardLayout {
        guard let board, let layout = BoardLayout(board: board) else {
            preconditionFailure("build guide step \(step) needs a picked board, has \(board ?? "none")")
        }
        return layout
    }

    private var pickBoard: some View {
        page("Pick your board", enabled: board.flatMap(BoardLayout.init(board:)) != nil) {
            Text("The one you have, or the one you'll get.")
                .foregroundStyle(.secondary)
            VStack(spacing: 12) {
                ForEach(BoardLayout.all, id: \.id) { layout in
                    BoardTile(layout: layout, selected: board == layout.id) { board = layout.id }
                }
            }
            Text("M5StickC Plus runs ShinerCore too, but this guide has no drawing of it yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var cable: some View {
        page("Grab a Grove cable and cut it in half") {
            OnboardingCard { GroveCableCutView().frame(height: 110) }
            Text("The board's Grove socket carries everything the strip needs. A Grove cable is the simplest way to reach it.")
            Text("Cut it in the middle, and bare the ends of the red, black and yellow wires.")
            WebLink("About Grove cables", url: URL(string: "https://docs.m5stack.com/en/accessory/cable/Grove_Cable")!)
        }
    }

    private var solder: some View {
        page("Solder it to the strip") {
            OnboardingCard { StripSolderView().frame(height: 150) }
            Text("Any WS2812 strip works, also sold as NeoPixel.")
            VStack(spacing: 0) {
                WireRow(color: .red, wire: "Red", pad: "+ (5V)")
                Divider().padding(.leading, 56)
                WireRow(color: .black, wire: "Black", pad: "− (GND)")
                Divider().padding(.leading, 56)
                WireRow(color: .yellow, wire: "Yellow", pad: "Data In (DIN)")
            }
            .background(Color.groupedSurface, in: .rect(cornerRadius: 16))
            Text("The arrows printed on the strip point away from Data In. Solder at the end where the arrows start; the other end won't light up.")
            Text("The strip prints a name by each pad. Go by the names; the order can differ from the drawing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var plugIn: some View {
        let layout = layout
        let tint = RoleKind.leds.tint
        return page("Plug it in") {
            OnboardingCard {
                BoardFaceView(board: layout, emphasis: [layout.ledPin: tint], groveTint: tint)
                    .frame(height: 200)
                    .accessibilityHidden(true)
            }
            Text("Plug the cable into the \(layout.name)'s Grove socket.")
            Text("ShinerCore sends the strip its colors through \(layout.location(of: layout.ledPin, grove: true)). That pin drives LEDs out of the box, so there is nothing to set up.")
        }
    }

    private var powerUp: some View {
        page("Power it up and find it", next: "Back to the list") {
            SearchingPulse()
                .frame(width: 140, height: 140)
                .frame(maxWidth: .infinity)
            Text("Plug the board into USB power and hold your phone close. Your core shows up in the list; tap it to play.")
            Text("Buttons, switches and knobs go on the white wire or the headers. Set them up later, in the core's Wiring tab.")
                .foregroundStyle(.secondary)
        }
    }
}

/// A board to pick: its drawing, its name, and a check when picked.
private struct BoardTile: View {
    let layout: BoardLayout
    let selected: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 16) {
                BoardFaceView(board: layout, emphasis: [:])
                    .frame(width: 200, height: 200)
                    .scaleEffect(0.42)
                    .frame(width: 84, height: 84)
                Text(layout.name).font(.title3.weight(.semibold))
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.groupedSurface, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0)
            }
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layout.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One wire of the Grove cable and the strip pad it goes to.
private struct WireRow: View {
    let color: Color
    let wire: String
    let pad: String

    var body: some View {
        HStack(spacing: 14) {
            Capsule()
                .fill(color)
                .overlay { Capsule().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1) }
                .frame(width: 26, height: 10)
            Text(wire).font(.headline)
            Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(pad).font(.body.weight(.medium))
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }
}

#Preview("1 Pick your board") {
    @Previewable @State var board: String? = "atom-lite"
    NavigationStack { BuildGuideStepView(step: .board, board: $board) {} }
}

#Preview("2 Grove cable") {
    NavigationStack { BuildGuideStepView(step: .cable, board: .constant("atom-lite")) {} }
}

#Preview("3 Solder") {
    NavigationStack { BuildGuideStepView(step: .solder, board: .constant("atom-lite")) {} }
}

#Preview("4 Plug it in, AtomS3 Lite") {
    NavigationStack { BuildGuideStepView(step: .plugIn, board: .constant("atoms3-lite")) {} }
}

#Preview("5 Power it up") {
    NavigationStack { BuildGuideStepView(step: .powerUp, board: .constant("atom-lite")) {} }
}
