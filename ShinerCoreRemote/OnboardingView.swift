import SwiftUI
import ShinerCoreKit

/// A screen of onboarding, in the order a newcomer meets them.
enum OnboardingScreen: Hashable {
    case whatItIs, howItWorks, tryIt
    case guide(BuildGuideStep)

    /// The three pages before the build guide, in order.
    static let pages: [OnboardingScreen] = [.whatItIs, .howItWorks, .tryIt]

    /// The screens pushed on the way to this one, so that a stack opened here still has a working Back.
    var path: [OnboardingScreen] {
        switch self {
        case .whatItIs: []
        case .howItWorks: [.howItWorks]
        case .tryIt: [.howItWorks, .tryIt]
        case .guide(let step): [.howItWorks] + BuildGuideStep.allCases.filter { $0.rawValue <= step.rawValue }.map(Self.guide)
        }
    }
}

/// Where onboarding opens: a screen, and the board id that the build guide has picked, if any.
struct OnboardingStart: Identifiable, Hashable {
    var screen = OnboardingScreen.whatItIs
    var board: String?
    var id: Self { self }
}

/// What ShinerCore is, its four steps, the demo core and the build guide, in a sheet.
/// Persists nothing: every open starts from `start`.
struct OnboardingView: View {
    /// Called after onboarding closes, to open the demo core.
    let tryDemo: () -> Void
    @State private var path: [OnboardingScreen]
    @State private var board: String?
    @Environment(\.dismiss) private var dismiss

    init(start: OnboardingStart = OnboardingStart(), tryDemo: @escaping () -> Void) {
        self.tryDemo = tryDemo
        _path = State(initialValue: start.screen.path)
        _board = State(initialValue: start.board)
    }

    var body: some View {
        NavigationStack(path: $path) {
            screen(.whatItIs)
                .navigationDestination(for: OnboardingScreen.self, destination: screen)
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 680)
        #endif
    }

    private func screen(_ screen: OnboardingScreen) -> some View {
        Group {
            switch screen {
            case .whatItIs:
                WhatItIsPage { path.append(.howItWorks) }
            case .howItWorks:
                HowItWorksPage(openGuide: openGuide) { path.append(.tryIt) }
            case .tryIt:
                TryItPage(openGuide: openGuide) {
                    dismiss()
                    tryDemo()
                }
            case .guide(let step):
                BuildGuideStepView(step: step, board: $board) {
                    if let next = step.next { path.append(.guide(next)) } else { dismiss() }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func openGuide() { path.append(.guide(.board)) }
}

/// One onboarding screen: a title, scrolling content, and a big button that moves on.
struct OnboardingPage<Content: View>: View {
    let title: String
    /// Shows the build guide's progress above the title.
    var guideStep: BuildGuideStep?
    let next: String
    var nextEnabled = true
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let guideStep { GuideProgress(step: guideStep) }
                Text(title)
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                content
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground)
        .safeAreaInset(edge: .bottom) {
            Button(action: action) {
                Text(next).font(.headline).frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!nextEnabled)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(Color.groupedBackground)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct GuideProgress: View {
    let step: BuildGuideStep
    private let count = BuildGuideStep.allCases.count

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Build guide · Step \(step.rawValue) of \(count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
            HStack(spacing: 6) {
                ForEach(1 ... count, id: \.self) { i in
                    Capsule()
                        .fill(i <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Build guide, step \(step.rawValue) of \(count)")
    }
}

/// A drawing or picture on its own rounded card.
struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.groupedSurface, in: .rect(cornerRadius: 20))
    }
}

// MARK: - Pages

struct WhatItIsPage: View {
    let next: () -> Void

    var body: some View {
        OnboardingPage(title: "ShinerCore", next: "How it works", action: next) {
            HStack(spacing: 12) {
                photo("Jacket", label: "A jacket lined with glowing LED strips")
                photo("Festival", label: "A glowing costume at a festival at night")
            }
            Text("Lights you wear, or build into things, played from your phone.")
                .font(.title3.weight(.medium))
            Text("Colors and animations change on the strip as you touch them.")
                .foregroundStyle(.secondary)
        }
    }

    private func photo(_ name: String, label: String) -> some View {
        Color.clear
            .frame(height: 280)
            .overlay { Image(name).resizable().scaledToFill() }
            .clipShape(.rect(cornerRadius: 20))
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
    }
}

struct HowItWorksPage: View {
    let openGuide: () -> Void
    let next: () -> Void
    private static let home = URL(string: "https://nevyn.dev/shinercore")!

    var body: some View {
        OnboardingPage(title: "How it works", next: "Next", action: next) {
            VStack(alignment: .leading, spacing: 0) {
                StoryStep(number: 1, title: "Get a board") {
                    Text("A small M5Stack board.")
                    WebLink("Which boards", url: Self.home)
                }
                Divider().padding(.leading, 68)
                StoryStep(number: 2, title: "Put ShinerCore on it") {
                    Text("With ShinerCore Flasher on a Mac, over USB.")
                    WebLink("Get the Flasher", url: Self.home)
                }
                Divider().padding(.leading, 68)
                StoryStep(number: 3, title: "Connect an LED strip") {
                    Text("Three wires and a little soldering.")
                    Button("Open the build guide", systemImage: "wrench.and.screwdriver", action: openGuide)
                        .buttonStyle(.bordered)
                        .foregroundStyle(.tint)
                        .padding(.top, 4)
                }
                Divider().padding(.leading, 68)
                StoryStep(number: 4, title: "Play") {
                    Text("Find your core in this app and light it up.")
                }
            }
            .background(Color.groupedSurface, in: .rect(cornerRadius: 20))
        }
    }
}

/// A link that leaves the app: tinted, with an outward arrow.
struct WebLink: View {
    let title: String
    let url: URL

    init(_ title: String, url: URL) {
        self.title = title
        self.url = url
    }

    var body: some View {
        Link(destination: url) {
            Label(title, systemImage: "arrow.up.right.square")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.tint)
        .padding(.vertical, 4)
    }
}

/// One of getting started's four steps: a numbered circle, a title, and what it takes.
private struct StoryStep<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.title3.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                content
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }
}

struct TryItPage: View {
    let openGuide: () -> Void
    let tryDemo: () -> Void

    private static let rainbow = LayerLook(animation: "Rainbow", color1: PixelColor(r: 0, g: 0, b: 0),
                                           color2: PixelColor(r: 0, g: 0, b: 0), speed: 6, tau: 2, phi: 1)

    var body: some View {
        OnboardingPage(title: "Try it now", next: "Try the demo core", action: tryDemo) {
            StripPreview(looks: [Self.rainbow], pixelCount: 60)
                .frame(height: 64)
            Text("The demo core plays like a real one, with its strip drawn on screen. No hardware needed.")
                .font(.title3.weight(.medium))
            VStack(alignment: .leading, spacing: 12) {
                Text("Ready to build?").font(.headline)
                Text("The build guide shows you how to connect an LED strip to a board, step by step.")
                    .foregroundStyle(.secondary)
                Button("Open the build guide", systemImage: "wrench.and.screwdriver", action: openGuide)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.groupedSurface, in: .rect(cornerRadius: 20))
        }
    }
}

#Preview("What it is") {
    NavigationStack { WhatItIsPage {} }
}

#Preview("How it works") {
    NavigationStack { HowItWorksPage(openGuide: {}) {} }
}

#Preview("Try it now") {
    NavigationStack { TryItPage(openGuide: {}) {} }
}

#Preview("Onboarding sheet") {
    Color.clear.sheet(isPresented: .constant(true)) { OnboardingView {} }
}
