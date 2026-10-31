import SwiftUI
import ShinerCoreKit

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if let screen = PlaygroundScreen.fromLaunchArguments {
                    PlaygroundRoot(screen: screen)
                } else if let demo = DemoMode.fromLaunchArguments {
                    DemoRoot(mode: demo)
                } else {
                    CoreListView()
                }
                #else
                CoreListView()
                #endif
            }
            .tint(.accentColor)  // toggles and form pickers ignore the asset accent without it
        }
    }
}

#if DEBUG
/// Simulators and build machines have no Bluetooth, so these launch
/// arguments drive the real UI against a `FakeCoreLink`. Every screen worth
/// looking at is reachable by argument alone — no tapping — which is what
/// lets Scripts/screenshots.sh capture the whole set unattended.
enum DemoMode: Equatable {
    /// `-demo`, or `-demo-tab animation|core|mesh|wiring`
    case controls(CoreControlsView.Tab)
    /// `-demo-offline`: connected UI in its reconnecting state
    case offline
    /// `-demo-list`: the discovery list; `-demo-list-empty`: the list before any core shows up
    case list(empty: Bool)

    /// `-demo-animation <name>`: the demo layer's animation; a name the render library
    /// doesn't know shows the no-preview state.
    static var animation: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-demo-animation") else { return nil }
        guard args.indices.contains(flag + 1) else { preconditionFailure("-demo-animation wants an animation name") }
        return args[flag + 1]
    }

    static var fromLaunchArguments: DemoMode? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demo-offline") { return .offline }
        if args.contains("-demo-list") { return .list(empty: false) }
        if args.contains("-demo-list-empty") { return .list(empty: true) }
        if let flag = args.firstIndex(of: "-demo-tab"), args.indices.contains(flag + 1) {
            guard let tab = CoreControlsView.Tab(rawValue: args[flag + 1]) else {
                preconditionFailure("-demo-tab wants one of \(CoreControlsView.Tab.allCases.map(\.rawValue))")
            }
            return .controls(tab)
        }
        if args.contains("-demo") { return .controls(.animation) }
        return nil
    }
}

struct DemoRoot: View {
    let mode: DemoMode
    @State private var link = FakeCoreLink.demo()
    @State private var session: CoreSession?

    private static let cores = [
        (DiscoveredCore(id: UUID(), name: "Vindarnas hus"), -58),
        (DiscoveredCore(id: UUID(), name: "Nevyn's jacket"), -71),
        (DiscoveredCore(id: UUID(), name: "Demo core"), -83),
    ]

    var body: some View {
        switch mode {
        case .list(let empty):
            CoreListView(browser: CoreBrowser(previewCores: empty ? [] : Self.cores,
                                              linkFactory: { _ in FakeCoreLink.demo() }))
        case .controls(let tab):
            controls(tab: tab)
        case .offline:
            controls(tab: .animation)
        }
    }

    private func controls(tab: CoreControlsView.Tab) -> some View {
        NavigationStack {
            if let session {
                CoreControlsView(session: session, tab: tab)
                    .navigationTitle("Nevyn's jacket")
            }
        }
        .task {
            if mode == .offline { link.becomeUnreachable() }
            if let animation = DemoMode.animation { link.values[CoreProps.animation.id] = animation }
            let session = CoreSession(link: link)
            self.session = session
            await session.run()
        }
    }
}
#endif
