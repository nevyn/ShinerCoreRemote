import SwiftUI
import ShinerCoreKit

struct CoreControlsView: View {
    enum Tab: String, CaseIterable { case animation, core, mesh, wiring }

    let session: CoreSession
    @State private var tab: Tab

    init(session: CoreSession, tab: Tab = .animation) {
        self.session = session
        _tab = State(initialValue: tab)
    }

    var body: some View {
        // .disabled sits on the tab contents, not the TabView, so the user
        // can still switch tabs while reconnecting.
        TabView(selection: $tab) {
            AnimationSettingsView(session: session)
                .disabled(session.connection != .connected)
                .tabItem { Label("Animation", systemImage: "sparkles") }
                .tag(Tab.animation)
            CoreSettingsView(session: session)
                .disabled(session.connection != .connected)
                .tabItem { Label("Core", systemImage: "gearshape") }
                .tag(Tab.core)
            MeshSettingsView(session: session)
                .disabled(session.connection != .connected)
                .tabItem { Label("Mesh", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(Tab.mesh)
            WiringView(session: session)
                .disabled(session.connection != .connected)
                .tabItem { Label("Wiring", systemImage: "cable.connector") }
                .tag(Tab.wiring)
        }
        .safeAreaInset(edge: .top, spacing: 0) { banner }
    }

    @ViewBuilder private var banner: some View {
        switch session.connection {
        case .connecting, .reconnecting:
            HStack {
                ProgressView()
                Text(session.connection == .connecting ? "Connecting…" : "Reconnecting…")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(.orange.opacity(0.25))
        case .failed(let reason):
            Label(reason, systemImage: "xmark.octagon.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(.red.opacity(0.25))
        case .connected:
            if let error = session.lastError {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                    Spacer()
                    Button("Dismiss") { session.lastError = nil }
                        .font(.subheadline)
                }
                .padding(8)
                .background(.red.opacity(0.25))
            }
        }
    }
}

/// Properties of the physical core itself, independent of animation.
struct CoreSettingsView: View {
    let session: CoreSession

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow {
                        ToggleBox(title: "Lights on", session: session, key: CoreProps.mode,
                                  heldBy: session.state.lightsHold?.pin)
                        NameBox(title: "Owner's name", session: session, key: CoreProps.name,
                                alertTitle: "Change core's name",
                                prompt: "Enter your name",
                                message: "Use your own nickname, and the core will rename itself to say it belongs to you.")
                    }
                    GridRow {
                        IntSliderBox(title: "Brightness", session: session, key: CoreProps.brightness, range: 0 ... 255)
                        IntSliderBox(title: "Number of LEDs", session: session, key: CoreProps.ledCount, range: 0 ... 800)
                    }
                    GridRow {
                        MenuBox(title: "LED order", session: session, key: CoreProps.ledOrder,
                                options: session.state.documentation?.ledColorOrders ?? [])
                        ToggleBox(title: "Microphone (beat detection)", session: session, key: CoreProps.mic)
                    }
                    GridRow {
                        PowerOnPresetBox(session: session)
                            .gridCellColumns(2)
                    }
                    GridRow {
                        IntSliderBox(title: "Power cap (mA, 0 = off)", session: session, key: CoreProps.maxCurrent, range: 0 ... 10000)
                            .gridCellColumns(2)
                    }
                }
            }
            .padding()
        }
    }
}

/// ESP-NOW mesh sync: the radio itself, and the shared preset carousel.
struct MeshSettingsView: View {
    let session: CoreSession

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow {
                        ToggleBox(title: "Mesh radio", session: session, key: CoreProps.mesh)
                        ToggleBox(title: "Play shared show", session: session, key: CoreProps.meshShow)
                    }
                    GridRow {
                        NameBox(title: "Group", session: session, key: CoreProps.meshGroup,
                                alertTitle: "Join a group",
                                prompt: "Camp or crew name",
                                message: "Cores only sync and share shows within the same group. Case and surrounding spaces don't matter. Leave empty to run with everyone else who left it empty.",
                                emptyLabel: "everyone")
                            .gridCellColumns(2)
                    }
                    // carouselBeats is deliberately absent: the firmware doesn't
                    // sync it between cores yet, so exposing it invites desync.
                }
            }
            .padding()
        }
    }
}

#Preview("Connected") {
    let session = CoreSession(link: FakeCoreLink.demo())
    NavigationStack {
        CoreControlsView(session: session)
            .navigationTitle("Vindarnas hus")
    }
    .task { await session.run() }
}

/// The Atom Lite demo's G22 switch also holds preset 0 on the Animation tab.
#Preview("Held by switches") {
    let link = FakeCoreLink.demo(board: .atomLite)
    link.values[CoreProps.pinStatus.id] = "0306004dff"  // G25 and G22 closed
    link.values[CoreProps.mode.id] = "0"
    let session = CoreSession(link: link)
    return NavigationStack {
        CoreControlsView(session: session, tab: .core)
            .navigationTitle("Vindarnas hus")
    }
    .task { await session.run() }
}

#Preview("Reconnecting") {
    let link = FakeCoreLink.demo()
    let session = CoreSession(link: link)
    NavigationStack {
        CoreControlsView(session: session)
            .navigationTitle("Vindarnas hus")
    }
    .task {
        link.becomeUnreachable()
        await session.run()
    }
}
