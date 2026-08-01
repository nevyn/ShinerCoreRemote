import SwiftUI
import ShinerCoreKit

struct CoreListView: View {
    @State private var browser: CoreBrowser
    @State private var selectedCore: DiscoveredCore?
    @Environment(\.scenePhase) private var scenePhase

    @MainActor init(browser: CoreBrowser = CoreBrowser()) {
        _browser = State(initialValue: browser)
    }

    var body: some View {
        NavigationSplitView {
            VStack {
                Label("To configure a ShinerCore's light animations, connect it to a power source (such as a power bank), and hold it near the phone. It will appear in the list below.", systemImage: "info.circle.fill")
                    .italic()
                    .padding()
                    .background(.blue.opacity(0.2))
                    .cornerRadius(16)

                if !browser.isBluetoothAvailable {
                    Label("Bluetooth is off or unavailable.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding(.top)
                }

                List(browser.discovered, selection: $selectedCore) { core in
                    NavigationLink(core.name, value: core)
                }
            }
            .navigationTitle("Nearby cores ✨")
            .background(Color.gray.opacity(0.1))
        } detail: {
            if let core = selectedCore {
                CoreDetailView(browser: browser, core: core)
            } else {
                Text("Select a core to continue")
            }
        }
        .onAppear { browser.startScanning() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                browser.refresh()  // prune powered-off cores, rescan
                browser.startScanning()
            case .background:
                browser.stopScanning()
            default:
                break
            }
        }
    }
}

#Preview {
    CoreListView(browser: CoreBrowser(previewCores: [
        DiscoveredCore(id: UUID(), name: "Vindarnas hus"),
        DiscoveredCore(id: UUID(), name: "Nevyn's jacket"),
    ]))
}
