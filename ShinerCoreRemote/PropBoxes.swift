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

struct ToggleBox: View {
    let title: String
    let session: CoreSession
    let key: PropertyKey<IntConverter>
    /// The pin of a closed switch that holds this value; disables the toggle.
    var heldBy: String?

    var body: some View {
        VStack {
            Toggle(title, isOn: session.boolBinding(key))
                .disabled(heldBy != nil)
            HeldCaption(pin: heldBy)
        }
        .propBox(key, in: session)
    }
}

/// Lets an installation that loses power reset itself: whenever the core
/// powers on, it turns its lights on and switches to the chosen preset.
struct PowerOnPresetBox: View {
    let session: CoreSession
    private let key = CoreProps.bootPreset
    private let resumes = -1

    var body: some View {
        let preset = session.state[key] ?? resumes
        VStack {
            Toggle("On power on, use preset", isOn: Binding(
                get: { preset != resumes },
                set: { session.set(key, to: $0 ? session.state[CoreProps.preset] ?? 0 : resumes) }
            ))
            Picker("Power-on preset", selection: Binding(
                get: { max(preset, 0) },
                set: { session.set(key, to: $0) }
            )) {
                ForEach(0..<5, id: \.self) { Text($0.description).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(preset == resumes)
            Text(preset == resumes ? "Powers on as it was left." : "Also turns the lights on.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .propBox(key, in: session)
    }
}

/// Says which wired switch is holding a setting, so the app can't change it.
struct HeldCaption: View {
    let pin: String?

    var body: some View {
        if let pin {
            Label("Held by the switch on \(pin)", systemImage: "switch.2")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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

/// A string property, edited via an alert.
struct NameBox: View {
    let title: String
    let session: CoreSession
    let key: PropertyKey<StringConverter>
    let alertTitle: String
    let prompt: String
    let message: String
    var emptyLabel = "…"
    @State private var editing = false
    @State private var name = ""

    var body: some View {
        VStack {
            Text(title).font(.headline)
            Button(action: {
                name = session.state[key] ?? ""
                editing = true
            }) {
                Label((session.state[key]?.isEmpty == false ? session.state[key]! : emptyLabel), systemImage: "square.and.pencil")
                    .font(.headline)
            }
            .alert(alertTitle, isPresented: $editing) {
                TextField(prompt, text: $name)
                Button("OK") { session.set(key, to: name) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(message)
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
        // tau and phi may be zero or negative, where log10 is undefined.
        let clamped = Binding(
            get: { min(max(value.wrappedValue, range.lowerBound), range.upperBound) },
            set: { value.wrappedValue = $0 })
        return self.init(
            value: clamped.logarithmic(),
            in: log10(range.lowerBound) ... log10(range.upperBound),
            onEditingChanged: onEditingChanged
        )
    }
}

extension Color {
    /// The page behind grouped content: light gray in light mode, black in dark.
    static var groupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    /// A tile or row on `groupedBackground`.
    static var groupedSurface: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}

extension Double {
    /// At most three significant digits: how a person reads a value at a glance.
    var plain: String { formatted(.number.precision(.significantDigits(1 ... 3))) }
}

/// A rounded card with a one-line header: title (and symbol) leading, value trailing.
struct SettingTile<Content: View>: View {
    let title: String
    var symbol: String?
    var value: String?
    @ViewBuilder var content: Content

    init(_ title: String, symbol: String? = nil, value: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.value = value
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let symbol {
                    Label(title, systemImage: symbol)
                } else {
                    Text(title)
                }
                Spacer(minLength: 4)
                if let value {
                    Text(value)
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            content
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(14)
        .background(Color.groupedSurface, in: .rect(cornerRadius: 16))
    }
}

/// Picks one word of a firmware-documented vocabulary (animation, blend mode, LED order).
/// A device value missing from the vocabulary stays listed rather than snapping to another.
struct VocabularyPicker: View {
    let title: String
    let session: CoreSession
    let key: PropertyKey<StringConverter>
    let options: [String]

    init(_ title: String, session: CoreSession, key: PropertyKey<StringConverter>, options: [String]) {
        self.title = title
        self.session = session
        self.key = key
        self.options = options
    }

    var body: some View {
        let current = session.state[key]
        Picker(title, selection: Binding(
            get: { current ?? "" },
            set: { session.set(key, to: $0) }
        )) {
            if current == nil { Text("…").tag("") }
            ForEach(Self.choices(options, current: current), id: \.self) { Text($0).tag($0) }
        }
    }

    static func choices(_ options: [String], current: String?) -> [String] {
        guard let current, !options.contains(current) else { return options }
        return options + [current]
    }
}

/// Speed while beat-synced: beats per cycle, snapped to musical detents.
enum BeatSpeed {
    static let detents: [Double] = [0.25, 0.5, 1, 2, 3, 4, 6, 8, 16]

    /// Nearest detent by log distance, matching the slider's log2 travel.
    static func snapped(_ value: Double) -> Double {
        detents.min { abs(log2($0 / value)) < abs(log2($1 / value)) }!
    }

    static func label(for beats: Double) -> String {
        switch beats {
        case 0.25: "¼ beat"
        case 0.5: "½ beat"
        case 1: "1 beat"
        default: "\(beats.plain) beats"
        }
    }
}
