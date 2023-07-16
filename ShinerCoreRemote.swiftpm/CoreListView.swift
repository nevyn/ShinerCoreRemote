import SwiftUI
import CoreBluetooth

struct CoreListView : View {
    @StateObject private var coreManager = CoreManager()
    @State private var cores: [ShinerCore] = []
    @State private var connectedCore: ShinerCore?
    
    var body: some View {
        NavigationView {
            VStack {
                List(cores, id: \.self) { core in
                    NavigationLink(
                        destination: CoreControlsView(core: core),
                        tag: core,
                        selection: $connectedCore
                    ) {
                        Text(core.localName)
                    }
                    .onTapGesture {
                        connect(to: core)
                    }
                }
            }
            .navigationTitle("Nearby cores ✨")
        }
        .onAppear {
            coreManager.foundCore = { core in
                cores.append(core)
            }
            
            coreManager.lostCore = { core in
                cores.removeAll { $0 == core }
            }
            coreManager.connectedCore = { core in 
                connectedCore = core
            }
        }
    }
    
    private func connect(to core: ShinerCore) {
        coreManager.centralManager.connect(core.device, options: nil)
    }
}

