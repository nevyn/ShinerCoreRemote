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
                SwitchPropBox(title: "Lights on", core: core, prop: core.mode)
                StringPropBox(title: "Owner's name", core: core, prop: core.name)
                ColorPropBox(title: "Primary color", core: core, prop: core.color)
                ColorPropBox(title: "Secondary color", core: core, prop: core.color2)
                DoubleLogSliderPropBox(title: "Speed", core: core, prop: core.speed, range: 0.01 ... 60.0)
                IntSliderPropBox(title: "Brightness", core: core, prop: core.brightness, range: 0.0 ... 255.0)
                DoubleLogSliderPropBox(title: "Tau", core: core, prop: core.tau, range: 0.01 ... 80.0)
                DoubleLogSliderPropBox(title: "Phi", core: core, prop: core.phi, range: 0.01 ... 80.0)
                
            }
        }
        .navigationBarTitle(core.localName)
    }
}

struct StringPropBox: View {
    let title: String
    let core: ShinerCore
    @ObservedObject var prop: CorePropertyBase
    @State private var editingAlert = false
    @State private var name = ""
    
    var body: some View {
        VStack {
            Text(title)
                .font(.headline)
                .padding()
            Button(action: changeAlert) {
                Label(prop.rawValue ?? "...", systemImage: "square.and.pencil")
                    .font(.headline)
            }
            .alert("Change core's name", isPresented: $editingAlert) {
                TextField("Enter your name", text: $name)
                Button("OK", action: submit)
            } message: {
                Text("Use your own nickname, and the core will rename itself to say it belongs to you.")
            }
        }
        .frame(minWidth: 100, maxWidth: .infinity, minHeight: 64)
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
    
    func changeAlert()
    {
        editingAlert = true
    }
    
    func submit()
    {
        core.write(newValue: name, to: prop)
    }
}

struct IntSliderPropBox: View {
    let title: String
    let core: ShinerCore
    @ObservedObject var prop: CoreProperty<IntConverter>
    let range: ClosedRange<Double>
    
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

struct SwitchPropBox: View {
    let title: String
    let core: ShinerCore
    @ObservedObject var prop: CoreProperty<IntConverter>
    
    var body: some View {
        VStack {
            Toggle(title, isOn: Binding(get: {
                guard let ret = prop.convertedValue() else { return false }
                return ret > 0 ? true : false
            }, set: { newValue in
                core.write(newValue: prop.unconvertedValue(value: newValue ? 1 : 0), to: prop)
            }))
        }
        .frame(minWidth: 100, maxWidth: .infinity, minHeight: 64)
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
}

struct DoubleSliderPropBox: View {
    let title: String
    let core: ShinerCore
    @ObservedObject var prop: CoreProperty<DoubleConverter>
    let range: ClosedRange<Double>
    
    var body: some View {
        VStack {
            Text(title)
                .font(.headline)
            Slider(
                value: Binding(get: {
                    prop.convertedValue() ?? range.lowerBound
                }, set: { newValue in 
                    core.write(newValue: prop.unconvertedValue(value: newValue), to: prop)
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

struct DoubleLogSliderPropBox: View {
    let title: String
    let core: ShinerCore
    @ObservedObject var prop: CoreProperty<DoubleConverter>
    let range: ClosedRange<Double>
    
    var body: some View {
        VStack {
            Text(title)
                .font(.headline)
            Slider.withLog10Scale(
                value: Binding(get: {
                    prop.convertedValue() ?? range.lowerBound
                }, set: { newValue in 
                    core.write(newValue: prop.unconvertedValue(value: newValue), to: prop)
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

struct ColorPropBox: View {
    let title: String
    let core: ShinerCore
    @ObservedObject var prop: CoreProperty<ColorConverter>
    
    var body: some View {
        VStack {
            ColorPicker(title, 
                selection: Binding(get: {
                prop.convertedValue() ?? Color.black 
                }, set: { newValue in 
                    core.write(newValue: prop.unconvertedValue(value: newValue), to: prop)
                })
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



// https://gist.github.com/prachigauriar/c508799bad359c3aa271ccc0865de231
extension Binding where Value == Double {
    func logarithmic(base: Double = 10) -> Binding<Double> {
        Binding(
            get: {
                log10(self.wrappedValue) / log10(base)
            },
            set: { newValue in
                self.wrappedValue = pow(base, newValue)
            }
        )
    }
}


extension Slider where Label == EmptyView, ValueLabel == EmptyView {
    static func withLog10Scale(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) -> Slider {
        return self.init(
            value: value.logarithmic(),
            in: log10(range.lowerBound) ... log10(range.upperBound),
            onEditingChanged: onEditingChanged
        )
    }
}
