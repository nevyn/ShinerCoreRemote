import SwiftUI
import ShinerCoreKit

struct CoreListView: View {
    @State private var browser: CoreBrowser
    @State private var selectedCore: DiscoveredCore?
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @Environment(\.scenePhase) private var scenePhase

    @MainActor init(browser: CoreBrowser = CoreBrowser()) {
        _browser = State(initialValue: browser)
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            Group {
                if browser.discovered.isEmpty {
                    LookingForCores(bluetoothAvailable: browser.isBluetoothAvailable, tryDemo: {
                        selectedCore = browser.demoCore
                        compactColumn = .detail  // there is no List to push the selection
                    })
                } else {
                    List(selection: $selectedCore) {
                        Section {
                            ForEach(browser.discovered) { core in
                                NavigationLink(value: core) {
                                    CoreRow(name: core.name, bars: browser.signalBars[core.id])
                                }
                            }
                        } header: {
                            if !browser.isBluetoothAvailable {
                                Label("Bluetooth is off or unavailable.", systemImage: "exclamationmark.triangle.fill")
                            }
                        } footer: {
                            Text("Missing one? Power it up and hold it close.")
                        }
                        Section {
                            NavigationLink(value: browser.demoCore) {
                                CoreRow(name: browser.demoCore.name, subtitle: "No hardware needed",
                                        symbol: "wand.and.stars", bars: nil)
                            }
                        }
                    }
                    // Pruning is explicit, never automatic: a core connected to
                    // someone else's phone stops advertising and couldn't rescan
                    // back into the list.
                    .refreshable { browser.refresh() }
                }
            }
            .navigationTitle("Nearby cores")
            .toolbar {
                Button("Rescan", systemImage: "arrow.clockwise") { browser.refresh() }
            }
        } detail: {
            if let core = selectedCore {
                CoreDetailView(browser: browser, core: core)
            } else {
                Text("Select a core to continue")
            }
        }
        .onChange(of: compactColumn) { _, column in
            if column == .sidebar { selectedCore = nil }  // as a List does when its pushed row pops
        }
        .onAppear { browser.startScanning() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                browser.startScanning()
            case .background:
                browser.stopScanning()
            default:
                break
            }
        }
    }
}

struct CoreRow: View {
    let name: String
    var subtitle: String?
    var symbol = "sparkles"
    /// 0-3, or nil before the first usable RSSI.
    let bars: Int?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.15), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let bars { SignalStrengthBars(bars: bars) }
        }
        .padding(.vertical, 6)
    }
}

struct SignalStrengthBars: View {
    let bars: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0 ..< 3) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < bars ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 4, height: CGFloat(6 + i * 4))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(["Barely in range", "Weak signal", "Good signal", "Close by"][min(max(bars, 0), 3)])
    }
}

/// The empty list: what to do, while the scan runs, and a way into the demo core.
struct LookingForCores: View {
    let bluetoothAvailable: Bool
    let tryDemo: () -> Void

    var body: some View {
        Group {
            if bluetoothAvailable {
                VStack(spacing: 16) {
                    SearchingPulse().frame(width: 160, height: 160)
                    Text("Looking for cores").font(.title2.weight(.semibold))
                    Text("Power up a core and hold it close to your phone.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    demoButton.padding(.top, 24)
                }
                .padding(.horizontal, 32)
            } else {
                ContentUnavailableView {
                    Label("Bluetooth is off", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Turn on Bluetooth to find nearby cores.")
                } actions: {
                    demoButton
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.groupedBackground)
    }
}

private extension LookingForCores {
    var demoButton: some View {
        Button("Try the demo core", systemImage: "wand.and.stars", action: tryDemo)
            .buttonStyle(.bordered)
            .controlSize(.large)
    }
}

/// Rings expanding from a radio symbol; holds still under Reduce Motion.
struct SearchingPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0.6 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0 ..< 3) { i in
                    let phase = (t / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(Color.accentColor.opacity(1 - phase), lineWidth: 2)
                        .scaleEffect(0.3 + 0.7 * phase)
                }
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.tint)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Cores") {
    CoreListView(browser: CoreBrowser(previewCores: [
        (DiscoveredCore(id: UUID(), name: "Nevyn's jacket"), -52),
        (DiscoveredCore(id: UUID(), name: "Vindarnas hus"), -70),
        (DiscoveredCore(id: UUID(), name: "Porch lights"), -84),
    ]))
}

#Preview("Empty") {
    CoreListView(browser: CoreBrowser(previewCores: []))
}

#Preview("Empty, Bluetooth off") {
    LookingForCores(bluetoothAvailable: false, tryDemo: {})
}
