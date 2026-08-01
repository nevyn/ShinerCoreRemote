import SwiftUI
import ShinerCoreKit

/// Owns a session for exactly as long as it is on screen: the `.task`
/// starting the session is cancelled when this view goes away, which
/// disconnects. Back = disconnect; visible = keep (re)connecting.
struct CoreDetailView: View {
    let browser: CoreBrowser
    let core: DiscoveredCore
    @State private var session: CoreSession?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let session {
                CoreControlsView(session: session)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(core.name)
        .task(id: core.id) {
            let session = browser.makeSession(for: core)
            self.session = session
            await session.run()
        }
        .onChange(of: scenePhase) { _, phase in
            // The link may survive backgrounding, but the device state may
            // have moved on; if it didn't survive, run() is already reconnecting.
            if phase == .active { session?.refresh() }
        }
    }
}
