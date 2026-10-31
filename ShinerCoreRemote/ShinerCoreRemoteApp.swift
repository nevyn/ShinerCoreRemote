import SwiftUI
import ShinerCoreKit

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if let demo = DemoMode.fromLaunchArguments {
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
    /// `-demo`, or `-demo-tab play|wiring|setup`
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

    /// `-demo-loading`: connected, but no read ever answers, so every control shows
    /// its loading state. Combines with `-demo-tab`.
    static var loading: Bool { ProcessInfo.processInfo.arguments.contains("-demo-loading") }

    /// `-demo-editor <layer>`: Play with the layer editor open on that layer.
    static var editor: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-demo-editor") else { return nil }
        guard args.indices.contains(flag + 1), let layer = Int(args[flag + 1]), (0 ..< CoreProps.layerCount).contains(layer) else {
            preconditionFailure("-demo-editor wants a layer, 0-\(CoreProps.layerCount - 1)")
        }
        return layer
    }

    /// `-demo-neighbor`: the mesh carousel plays a neighbor's preset.
    static var neighbor: Bool { ProcessInfo.processInfo.arguments.contains("-demo-neighbor") }

    /// `-demo-legacy`: firmware that predates the layer summary.
    static var legacy: Bool { ProcessInfo.processInfo.arguments.contains("-demo-legacy") }

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
        if args.contains("-demo") || loading || editor != nil || neighbor || legacy { return .controls(.play) }
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
            controls(tab: .play)
        }
    }

    private func controls(tab: CoreControlsView.Tab) -> some View {
        NavigationStack {
            if let session {
                CoreControlsView(session: session, tab: tab, editing: DemoMode.editor)
                    .navigationTitle("Nevyn's jacket")
            }
        }
        .task {
            if mode == .offline { link.becomeUnreachable() }
            if DemoMode.loading { link.deferReads = true }
            if let animation = DemoMode.animation { link.values[CoreProps.animation.id] = animation }
            if let layer = DemoMode.editor { link.values[CoreProps.layer.id] = String(layer) }
            if DemoMode.legacy { link.exposesLayerSummary = false }
            let session = CoreSession(link: link)
            self.session = session
            if DemoMode.neighbor {
                // After the core's own stack has been read, as when the carousel moves on.
                Task {
                    while session.state.ownLayerSummary == nil {
                        do { try await Task.sleep(for: .milliseconds(50)) } catch { return }  // cancelled: the demo closed
                    }
                    link.neighborLayers = [FakeCoreLink.layer("Rainbow", color: "0 0 0", speed: 6, tau: 2, phi: 1),
                                           FakeCoreLink.layer("Twinkle", color: "255 255 255", color2: "255 180 60",
                                                              speed: 1, tau: 6, phi: 1)]
                }
            }
            await session.run()
        }
    }
}
#endif
