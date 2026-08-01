import SwiftUI
import ShinerCoreKit

struct CoreControlsView: View {
    let session: CoreSession

    var body: some View {
        TabView {
            AnimationSettingsView(session: session)
                .tabItem { Label("Animation", systemImage: "sparkles") }
            CoreSettingsView(session: session)
                .tabItem { Label("Core", systemImage: "gearshape") }
        }
        .disabled(session.connection != .connected)
        .safeAreaInset(edge: .top, spacing: 0) { banner }
    }

    @ViewBuilder private var banner: some View {
        if session.connection != .connected {
            HStack {
                ProgressView()
                Text(session.connection == .connecting ? "Connecting…" : "Reconnecting…")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(.orange.opacity(0.25))
        } else if let error = session.lastError {
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

/// Everything that shapes the current animation, per preset and layer.
struct AnimationSettingsView: View {
    let session: CoreSession

    var body: some View {
        let docs = session.state.documentation
        ScrollView {
            VStack(spacing: 16) {
                PickerRow(
                    title: "Preset", count: 5,
                    key: CoreProps.preset, session: session)
                PickerRow(
                    title: "Layer", count: 10,
                    key: CoreProps.layer, session: session)

                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow {
                        ColorBox(title: "Primary color", session: session, key: CoreProps.color)
                        ColorBox(title: "Secondary color", session: session, key: CoreProps.color2)
                    }
                    GridRow {
                        MenuBox(title: "Blend mode", session: session, key: CoreProps.blendMode,
                                options: docs?.blendModes ?? [])
                        MenuBox(title: "Animation", session: session, key: CoreProps.animation,
                                options: docs?.animations ?? [])
                    }
                    GridRow {
                        ToggleBox(title: "Beat sync", session: session, key: CoreProps.beatSync)
                        LogSliderBox(
                            title: (session.state[CoreProps.beatSync] ?? 0) > 0
                                ? "Speed (beats per cycle)" : "Speed (seconds per cycle)",
                            session: session, key: CoreProps.speed, range: 0.01 ... 60.0)
                    }
                    GridRow {
                        LogSliderBox(title: "Tau", session: session, key: CoreProps.tau, range: 0.01 ... 80.0)
                        LogSliderBox(title: "Phi", session: session, key: CoreProps.phi, range: 0.01 ... 80.0)
                    }
                }
            }
            .padding()
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
                        ToggleBox(title: "Lights on", session: session, key: CoreProps.mode)
                        NameBox(title: "Owner's name", session: session, key: CoreProps.name)
                    }
                    GridRow {
                        IntSliderBox(title: "Brightness", session: session, key: CoreProps.brightness, range: 0 ... 255)
                        IntSliderBox(title: "Number of LEDs", session: session, key: CoreProps.ledCount, range: 0 ... 800)
                    }
                    GridRow {
                        MenuBox(title: "LED order", session: session, key: CoreProps.ledOrder,
                                options: session.state.documentation?.ledColorOrders ?? [])
                    }
                }
            }
            .padding()
        }
    }
}

/// Segmented picker for layer/preset switches, whose device-side change
/// fans out to the other props (hence `select`, not `set`).
struct PickerRow: View {
    let title: String
    let count: Int
    let key: PropertyKey<IntConverter>
    let session: CoreSession

    var body: some View {
        HStack {
            Text(title + ":").font(.headline)
            Picker(title, selection: Binding(
                get: { session.state[key] ?? 0 },
                set: { session.select(key, $0) }
            )) {
                ForEach(0..<count, id: \.self) {
                    Text($0.description).tag($0)
                }
            }
            .pickerStyle(.segmented)
        }
        .availability(of: key, in: session)
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
