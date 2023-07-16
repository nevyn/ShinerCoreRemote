import SwiftUI
import CoreBluetooth

struct CoreControlsView: View {
    @ObservedObject var core: ShinerCore
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            StringPropBox(title: "Primary color", value: core.color)
            StringPropBox(title: "Secondary color", value: core.color2)
            StringPropBox(title: "Brightness", value: core.brightness)
            StringPropBox(title: "Mode", value: core.mode)
            StringPropBox(title: "Tau", value: core.tau)
            StringPropBox(title: "Phi", value: core.phi)
            StringPropBox(title: "Owner's name", value: core.name)
        }
        .navigationBarTitle(core.localName)
    }
}

struct StringPropBox: View {
    let title: String
    let value: String?
    
    var body: some View {
        VStack {
            Text(title)
                .font(.headline)
            Text(value ?? "...")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(minWidth: 100, maxWidth: .infinity, minHeight: 128)
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
}

struct SliderPropBox: View {
    let title: String
    let value: String?
    let range = 0.0...255.0
    
    var body: some View {
        VStack {
            Text(title)
                .font(.headline)
//            Slider() // TODO...
            Text(value ?? "...")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(minWidth: 100, maxWidth: .infinity, minHeight: 128)
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
}