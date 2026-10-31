import SwiftUI
import ShinerCoreKit

struct CoreControlsView: View {
    enum Tab: String, CaseIterable { case play, wiring, setup }

    let session: CoreSession
    @State private var tab: Tab
    /// The layer whose editor Play opens with.
    private let editing: Int?

    init(session: CoreSession, tab: Tab = .play, editing: Int? = nil) {
        self.session = session
        self.editing = editing
        _tab = State(initialValue: tab)
    }

    var body: some View {
        // .disabled sits on the tab contents, not the TabView, so the user
        // can still switch tabs while reconnecting.
        TabView(selection: $tab) {
            PlayView(session: session, editing: editing)
                .disabled(session.connection != .connected)
                .tabItem { Label("Play", systemImage: "sparkles") }
                .tag(Tab.play)
            WiringView(session: session)
                .disabled(session.connection != .connected)
                .tabItem { Label("Wiring", systemImage: "cable.connector") }
                .tag(Tab.wiring)
            SetupView(session: session)
                .disabled(session.connection != .connected)
                .tabItem { Label("Setup", systemImage: "slider.horizontal.3") }
                .tag(Tab.setup)
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

/// The things set once: who owns the core, its LED strip, sound and the mesh.
struct SetupView: View {
    let session: CoreSession

    var body: some View {
        let state = session.state
        let meshOff = (state[CoreProps.mesh] ?? 0) == 0
        Form {
            Section {
                LabeledContent("Owner") {
                    CommitField("Your name", session: session, key: CoreProps.name)
                }
                .availability(of: CoreProps.name, in: session)
                Picker("When powered on", selection: session.binding(CoreProps.bootPreset, default: -1)) {
                    Text("Resume as it was").tag(-1)
                    ForEach(0 ..< CoreProps.presetCount, id: \.self) { Text("Lights on, preset \($0)").tag($0) }
                }
                .availability(of: CoreProps.bootPreset, in: session)
            } header: {
                Text("This core")
            } footer: {
                Text("The core names itself after its owner.")
            }

            Section {
                LabeledContent("LEDs") {
                    HStack {
                        CommitField("Count", session: session, key: CoreProps.ledCount) {
                            min(max($0, 0), CoreProps.maxLEDCount)
                        }
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                        Stepper("LEDs", value: session.binding(CoreProps.ledCount, default: 0),
                                in: 0 ... CoreProps.maxLEDCount)
                            .labelsHidden()
                    }
                }
                .availability(of: CoreProps.ledCount, in: session)
                VocabularyPicker("LED order", session: session, key: CoreProps.ledOrder,
                                 options: state.documentation?.ledColorOrders ?? [])
                    .availability(of: CoreProps.ledOrder, in: session)
                Picker("Power cap", selection: session.binding(CoreProps.maxCurrent, default: 0)) {
                    ForEach(PowerCap.choices(current: state[CoreProps.maxCurrent]), id: \.self) {
                        Text(PowerCap.label(milliamps: $0)).tag($0)
                    }
                }
                .availability(of: CoreProps.maxCurrent, in: session)
            } header: {
                Text("LED strip")
            } footer: {
                Text("The power cap dims bright frames to fit an estimated current budget.")
            }

            Section {
                Toggle("Microphone", isOn: session.boolBinding(CoreProps.mic))
                    .availability(of: CoreProps.mic, in: session)
            } header: {
                Text("Sound")
            } footer: {
                Text("Needed for beat sync and Beat Pulse.")
            }

            Section {
                Toggle("Mesh radio", isOn: session.boolBinding(CoreProps.mesh))
                    .availability(of: CoreProps.mesh, in: session)
                Toggle("Play the shared show", isOn: session.boolBinding(CoreProps.meshShow))
                    .disabled(meshOff)
                    .availability(of: CoreProps.meshShow, in: session)
                LabeledContent("Group") {
                    CommitField("Everyone", session: session, key: CoreProps.meshGroup)
                }
                .disabled(meshOff)
                .availability(of: CoreProps.meshGroup, in: session)
                // carouselBeats is deliberately absent: the firmware doesn't
                // sync it between cores yet, so exposing it invites desync.
            } header: {
                Text("Mesh")
            } footer: {
                Text("Cores in the same group sync with each other and take turns choosing the show. Leave the group empty to join everyone else who left it empty.")
            }
        }
        .formStyle(.grouped)
    }
}

/// The current limits that the power cap offers, in mA; 0 is no cap.
enum PowerCap {
    static let limits = [0, 500, 1000, 1500, 2000, 3000, 4000, 5000]

    /// `limits`, plus a stored value that isn't one of them, so it shows as it is.
    static func choices(current: Int?) -> [Int] {
        guard let current, !limits.contains(current) else { return limits }
        return (limits + [current]).sorted()
    }

    static func label(milliamps: Int) -> String {
        milliamps == 0 ? "None" : "\((Double(milliamps) / 1000).formatted(.number.precision(.fractionLength(0 ... 3)))) A"
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

#Preview("Setup") {
    let session = CoreSession(link: FakeCoreLink.demo())
    NavigationStack {
        CoreControlsView(session: session, tab: .setup)
            .navigationTitle("Nevyn's jacket")
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
