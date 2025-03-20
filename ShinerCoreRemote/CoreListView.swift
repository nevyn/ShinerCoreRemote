import SwiftUI
import CoreBluetooth

struct CoreListView : View {
    @StateObject private var coreManager = CoreManager()
    @State private var cores: [ShinerCore] = []
    @State private var connectedCore: ShinerCore?
    @State private var selectedCore: ShinerCore?
    
    var body: some View {
        NavigationSplitView {
            VStack {
                Label("To configure a ShinerCore's light animations, connect it to a power source (such as a power bank), and hold it near the phone. It will appear in the list below.", systemImage: "info.circle.fill")
                    .italic(true)
                    .padding()
                    .background(.blue.opacity(0.2))
                    .cornerRadius(16)

                List(cores, selection: $selectedCore) { core in
                    NavigationLink(core.localName, value: core)
                }
            }
            .navigationTitle("Nearby cores ✨")
            .background(Color.gray.opacity(0.1))
        } detail: {
            if let core = selectedCore
            {
                CoreControlsView(core: core)
            }
            else
            {
                Text("Select a core to continue")
            }
        }
        .onAppear {
            coreManager.foundCore = { core in
                cores.append(core)
            }
            
            coreManager.lostCore = { core in
                cores.removeAll { $0 == core }
            }
            coreManager.disconnectedCore = { core in
                if core == connectedCore
                {
                    connectedCore = nil
                }
            }
            coreManager.connectedCore = { core in 
                connectedCore = core
            }
        }
        .onChange(of: selectedCore) { newValue in 
            if let core = connectedCore
            {
                coreManager.disconnect(from: core)
            }
            if let core = selectedCore
            {
                coreManager.connect(to: core)
            }
        }
    }
    
    private func connect(to core: ShinerCore) {
        coreManager.centralManager.connect(core.device, options: nil)
    }
}

