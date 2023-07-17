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
            StringPropBox(title: "Primary color", prop: core.color)
            StringPropBox(title: "Secondary color", prop: core.color2)
            SliderPropBox(title: "Brightness", prop: core.brightness)
            StringPropBox(title: "Mode", prop: core.mode)
            StringPropBox(title: "Tau", prop: core.tau)
            StringPropBox(title: "Phi", prop: core.phi)
            StringPropBox(title: "Owner's name", prop: core.name)
        }
        .navigationBarTitle(core.localName)
    }
}

struct StringPropBox: View {
    let title: String
    let prop: CorePropertyBase
    
    var body: some View {
        VStack {
            Text(title)
                .font(.headline)
            Text(prop.rawValue ?? "...")
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
    let prop: CoreProperty<DoubleConverter>
    @State var value: Double = 0.0
    let range = 0.0...255.0
    
    var body: some View {
        VStack {
            Text(title)
                .font(.headline)
            Slider(
                value: $value,
                in: range
            )
            Text(prop.rawValue ?? "...")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(minWidth: 100, maxWidth: .infinity, minHeight: 128)
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
        .onAppear {
            value = prop.convertedValue() ?? 0.0
        }
    }
}
