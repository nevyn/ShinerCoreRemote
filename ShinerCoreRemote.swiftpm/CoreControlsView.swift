import SwiftUI
import CoreBluetooth

struct CoreControlsView: View {
    let core: ShinerCore
    
    var body: some View {
        VStack {
            Text("Yooo")
                .font(.title)
                .navigationBarTitle(core.device.name ?? "Unknown")
        }
    }
  }
