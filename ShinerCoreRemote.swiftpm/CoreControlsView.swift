import SwiftUI
import CoreBluetooth

struct CoreControlsView: View {
    @ObservedObject var core: ShinerCore
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                StringPropBox(title: "Primary color", core: core, prop: core.color)
                StringPropBox(title: "Secondary color", core: core, prop: core.color2)
                SliderPropBox(title: "Brightness", core: core, prop: core.brightness)
                StringPropBox(title: "Mode", core: core, prop: core.mode)
                StringPropBox(title: "Tau", core: core, prop: core.tau)
                StringPropBox(title: "Phi", core: core, prop: core.phi)
                StringPropBox(title: "Owner's name", core: core, prop: core.name)
            }
        }
        .navigationBarTitle(core.localName)
    }
}

struct StringPropBox: View {
    let title: String
    let core: ShinerCore
    @ObservedObject var prop: CorePropertyBase
    
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
    let core: ShinerCore
    @ObservedObject var prop: CoreProperty<IntConverter>
    let range = 0.0...255.0
    
    var body: some View {
        VStack {
            Text(title)
                .font(.headline)
            Slider(
                value: Binding(get: {
                    Double(prop.convertedValue() ?? 0)
                }, set: { newValue in 
                    core.write(newValue: prop.unconvertedValue(value: Int(newValue)), to: prop)
                }),
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
    }
}
