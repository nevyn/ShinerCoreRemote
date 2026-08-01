import SwiftUI
import ShinerCoreKit

extension View {
    /// Dim and disable a control whose property this firmware doesn't
    /// expose. Boxes stay in the layout either way: structural stability is
    /// what keeps scrolling from jumping as characteristic reads trickle in.
    func availability<C>(of key: PropertyKey<C>, in session: CoreSession) -> some View {
        let available = session.state.isAvailable(key)
        return self
            .disabled(!available)
            .opacity(available ? 1 : 0.35)
    }

    /// Shared prop-box chrome.
    func propBox<C>(_ key: PropertyKey<C>, in session: CoreSession) -> some View {
        self
            .frame(minWidth: 100, maxWidth: .infinity, minHeight: 100)
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
            .availability(of: key, in: session)
    }
}

/// The wire value, as a debugging-friendly caption.
struct RawValueText: View {
    let raw: String?
    var body: some View {
        Text(raw ?? "…")
            .font(.subheadline)
            .foregroundStyle(.gray)
    }
}

struct IntSliderBox: View {
    let title: String
    let session: CoreSession
    let key: PropertyKey<IntConverter>
    let range: ClosedRange<Double>

    var body: some View {
        VStack {
            Text(title).font(.headline)
            Slider(
                value: Binding(
                    get: { Double(session.state[key] ?? 0) },
                    set: { session.set(key, to: Int($0)) }
                ),
                in: range)
            RawValueText(raw: session.state.rawValue(of: key))
        }
        .propBox(key, in: session)
    }
}

struct LogSliderBox: View {
    let title: String
    let session: CoreSession
    let key: PropertyKey<DoubleConverter>
    let range: ClosedRange<Double>

    var body: some View {
        VStack {
            Text(title).font(.headline)
            Slider.withLog10Scale(
                value: Binding(
                    get: { session.state[key] ?? range.lowerBound },
                    set: { session.set(key, to: $0) }
                ),
                in: range)
            RawValueText(raw: session.state.rawValue(of: key))
        }
        .propBox(key, in: session)
    }
}

struct ToggleBox: View {
    let title: String
    let session: CoreSession
    let key: PropertyKey<IntConverter>

    var body: some View {
        Toggle(title, isOn: session.boolBinding(key))
            .propBox(key, in: session)
    }
}

struct ColorBox: View {
    let title: String
    let session: CoreSession
    let key: PropertyKey<ColorConverter>

    var body: some View {
        VStack {
            ColorPicker(title, selection: session.binding(key, default: .black))
            RawValueText(raw: session.state.rawValue(of: key))
        }
        .propBox(key, in: session)
    }
}

/// Chooser for a firmware-documented vocabulary (animation, blend mode,
/// LED order): step through with arrows or pick from the menu.
struct MenuBox: View {
    let title: String
    let session: CoreSession
    let key: PropertyKey<StringConverter>
    let options: [String]

    private var currentIndex: Int {
        session.state[key].flatMap(options.firstIndex(of:)) ?? 0
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            if options.isEmpty {
                RawValueText(raw: session.state.rawValue(of: key))
            } else {
                HStack(spacing: 12) {
                    Button(action: { step(-1) }) {
                        Image(systemName: "chevron.left.circle.fill").font(.title2)
                    }
                    .disabled(currentIndex <= 0)

                    Menu {
                        ForEach(options, id: \.self) { option in
                            Button(action: { session.set(key, to: option) }) {
                                HStack {
                                    Text(option)
                                    if option == session.state[key] {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(session.state[key] ?? "…")
                            .frame(minWidth: 80)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(6)
                    }

                    Button(action: { step(1) }) {
                        Image(systemName: "chevron.right.circle.fill").font(.title2)
                    }
                    .disabled(currentIndex >= options.count - 1)
                }
            }
        }
        .propBox(key, in: session)
    }

    private func step(_ delta: Int) {
        let index = currentIndex + delta
        guard options.indices.contains(index) else { return }
        session.set(key, to: options[index])
    }
}

/// The owner-name property, edited via an alert.
struct NameBox: View {
    let title: String
    let session: CoreSession
    let key: PropertyKey<StringConverter>
    @State private var editing = false
    @State private var name = ""

    var body: some View {
        VStack {
            Text(title).font(.headline)
            Button(action: {
                name = session.state[key] ?? ""
                editing = true
            }) {
                Label(session.state[key] ?? "…", systemImage: "square.and.pencil")
                    .font(.headline)
            }
            .alert("Change core's name", isPresented: $editing) {
                TextField("Enter your name", text: $name)
                Button("OK") { session.set(key, to: name) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Use your own nickname, and the core will rename itself to say it belongs to you.")
            }
        }
        .propBox(key, in: session)
    }
}

// https://gist.github.com/prachigauriar/c508799bad359c3aa271ccc0865de231
extension Binding where Value == Double {
    func logarithmic(base: Double = 10) -> Binding<Double> {
        Binding(
            get: { log10(self.wrappedValue) / log10(base) },
            set: { self.wrappedValue = pow(base, $0) }
        )
    }
}

extension Slider where Label == EmptyView, ValueLabel == EmptyView {
    static func withLog10Scale(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) -> Slider {
        self.init(
            value: value.logarithmic(),
            in: log10(range.lowerBound) ... log10(range.upperBound),
            onEditingChanged: onEditingChanged
        )
    }
}
