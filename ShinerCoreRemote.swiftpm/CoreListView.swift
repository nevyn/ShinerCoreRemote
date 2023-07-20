import SwiftUI
import CoreBluetooth

struct CoreListView : View {
    @StateObject private var coreManager = CoreManager()
    @State private var cores: [ShinerCore] = []
    @State private var connectedCore: ShinerCore?
    
    var body: some View {
        NavigationView {
            VStack {
                Label("To configure a ShinerCore's light animations, connect it to a power source (such as a power bank), and hold it near the phone. It will appear in the list below.", systemImage: "info.circle.fill")
                    .italic(true)
                    .padding()
                    .background(.blue.opacity(0.2))
                    .cornerRadius(16)

                
                
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
            .background(Color.gray.opacity(0.1))
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

