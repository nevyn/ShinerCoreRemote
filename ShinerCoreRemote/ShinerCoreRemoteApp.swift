import SwiftUI
import ShinerCoreKit

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Simulators have no Bluetooth; `-demo` / `-demo-offline` show the
            // controls against a FakeCoreLink for visual verification.
            if ProcessInfo.processInfo.arguments.contains("-demo") {
                DemoRoot(offline: false)
            } else if ProcessInfo.processInfo.arguments.contains("-demo-offline") {
                DemoRoot(offline: true)
            } else if ProcessInfo.processInfo.arguments.contains("-demo-list") {
                CoreListView(browser: CoreBrowser(
                    previewCores: [
                        DiscoveredCore(id: UUID(), name: "Vindarnas hus"),
                        DiscoveredCore(id: UUID(), name: "Nevyn's jacket"),
                        DiscoveredCore(id: UUID(), name: "Demo core"),
                    ],
                    linkFactory: { _ in FakeCoreLink.demo() }))
            } else {
                CoreListView()
            }
            #else
            CoreListView()
            #endif
        }
    }
}

#if DEBUG
struct DemoRoot: View {
    let offline: Bool
    @State private var link = FakeCoreLink.demo()
    @State private var session: CoreSession?

    var body: some View {
        NavigationStack {
            if let session {
                CoreControlsView(session: session)
                    .navigationTitle("Demo core")
            }
        }
        .task {
            if offline { link.becomeUnreachable() }
            let session = CoreSession(link: link)
            self.session = session
            await session.run()
        }
    }
}
#endif
