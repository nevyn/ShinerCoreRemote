import SwiftUI
import CoreBluetooth

struct CoreControlsView: View {
    let peripheral: CBPeripheral
    
    var body: some View {
        VStack {
            Text(peripheral.name ?? "Unknown")
                .font(.title)
                .navigationBarTitle(peripheral.name ?? "Unknown")
        }
    }
  }
