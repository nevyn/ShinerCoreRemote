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
                if core.ledOrder.available {
                    DropDownPropBox(title: "LED Order", core: core, prop: core.ledOrder, options: core.documentation.convertedValue()?.ledColorOrders ?? [])
                }
            }
            if core.layer.available {
                Picker("Layer",
                    selection: Binding(get: {
                        core.layer.convertedValue() ?? 0
                    }, set: { newValue in
                        let newLayer = Int(newValue)
                        
                        core.switchTo(layer: newLayer)
                    })) {
                        ForEach(1..<9) {
                            Text($0.description).tag($0)
                        }
                    }.pickerStyle(SegmentedPickerStyle()
                )
            }

            LazyVGrid(columns: columns, spacing: 16) {
                if core.color.available {
                    ColorPropBox(title: "Primary color", core: core, prop: core.color)
                }
                if core.color2.available {
                    ColorPropBox(title: "Secondary color", core: core, prop: core.color2)
                }
                if core.blendMode.available {
                    DropDownPropBox(title: "Blend Mode", core: core, prop: core.blendMode, options: core.documentation.convertedValue()?.blendModes ?? [])
                }
                if core.animation.available {
                    DropDownPropBox(title: "Animation", core: core, prop: core.animation, options: core.documentation.convertedValue()?.animations ?? [])
                }
                if core.speed.available {
                    DoubleLogSliderPropBox(title: "Speed", core: core, prop: core.speed, range: 0.01 ... 60.0)
                }
                if core.tau.available {
                    DoubleLogSliderPropBox(title: "Tau", core: core, prop: core.tau, range: 0.01 ... 80.0)
                }
                if core.phi.available {
                    DoubleLogSliderPropBox(title: "Phi", core: core, prop: core.phi, range: 0.01 ... 80.0)
                }
                if core.brightness.available {
                    IntSliderPropBox(title: "Brightness", core: core, prop: core.brightness, range: 0.0 ... 255.0)
                }
            }
        }
        .navigationTitle(core.localName)
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

struct DropDownPropBox: View {
    let title: String
    let core: ShinerCore
    @ObservedObject var prop: CoreProperty<StringConverter>
    let options: [String]
    
    private var currentIndex: Int {
        guard let current = prop.convertedValue() else { return 0 }
        return options.firstIndex(of: current) ?? 0
    }
    
    private var hasOptions: Bool {
        !options.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
            
            if hasOptions {
                // Stepper arrows with current value
                HStack(spacing: 12) {
                    Button(action: stepBackward) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title2)
                    }
                    .disabled(currentIndex <= 0)
                    
                    Menu {
                        ForEach(options, id: \.self) { option in
                            Button(action: {
                                core.write(newValue: option, to: prop)
                            }) {
                                HStack {
                                    Text(option)
                                    if option == prop.convertedValue() {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(prop.convertedValue() ?? "...")
                            .font(.body)
                            .frame(minWidth: 80)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(6)
                    }
                    
                    Button(action: stepForward) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title2)
                    }
                    .disabled(currentIndex >= options.count - 1)
                }
            } else {
                // Fallback: just show the raw value when options aren't available
                Text(prop.rawValue ?? "...")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 100, maxWidth: .infinity, minHeight: 100)
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
    
    private func stepBackward() {
        guard currentIndex > 0 else { return }
        let newValue = options[currentIndex - 1]
        core.write(newValue: newValue, to: prop)
    }
    
    private func stepForward() {
        guard currentIndex < options.count - 1 else { return }
        let newValue = options[currentIndex + 1]
        core.write(newValue: newValue, to: prop)
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
