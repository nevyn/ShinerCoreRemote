import SwiftUI
import ShinerCoreKit

extension View {
    /// Dim and disable a control whose property this firmware doesn't expose, and
    /// show it as a disabled placeholder until its value has been read, rather than an
    /// editable stand-in value. Controls stay in the layout either way: structural
    /// stability is what keeps scrolling from jumping as characteristic reads trickle in.
    func availability<C>(of key: PropertyKey<C>, in session: CoreSession) -> some View {
        let available = session.state.isAvailable(key)
        let loading = available && session.state[key] == nil
        return self
            .disabled(!available || loading)
            .redacted(reason: loading ? .placeholder : [])
            .opacity(available ? 1 : 0.35)
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

/// Edits a property as text and writes it when the user submits or leaves the
/// field, not per keystroke. Text that doesn't parse reverts to the core's value.
struct CommitField<C: PropertyConverter>: View {
    let prompt: String
    let session: CoreSession
    let key: PropertyKey<C>
    /// Applied to a parsed value before writing, e.g. to clamp it to the firmware's range.
    var adjust: (C.ValueType) -> C.ValueType = { $0 }
    @State private var text = ""
    @FocusState private var focused: Bool

    init(_ prompt: String, session: CoreSession, key: PropertyKey<C>,
         adjust: @escaping (C.ValueType) -> C.ValueType = { $0 }) {
        self.prompt = prompt
        self.session = session
        self.key = key
        self.adjust = adjust
    }

    var body: some View {
        let raw = session.state.rawValue(of: key) ?? ""
        TextField(prompt, text: $text)
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onChange(of: raw, initial: true) { _, newRaw in if !focused { text = newRaw } }
    }

    private func commit() {
        guard let value = C.convert(text.trimmingCharacters(in: .whitespaces)) else {
            text = session.state.rawValue(of: key) ?? ""
            return
        }
        let adjusted = adjust(value)
        session.set(key, to: adjusted)
        text = C.unconvert(adjusted)
    }
}
