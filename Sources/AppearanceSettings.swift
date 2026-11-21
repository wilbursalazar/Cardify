import SwiftUI
import AppKit

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case charcoal
    case slate
    case midnight

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    static let charcoalBackground = Color(red: 28 / 255, green: 27 / 255, blue: 35 / 255)
    static let charcoalText = Color(red: 202 / 255, green: 200 / 255, blue: 182 / 255)
    static let charcoalTeal = Color(red: 6 / 255, green: 126 / 255, blue: 137 / 255)
    static let charcoalBlue = Color(red: 148 / 255, green: 180 / 255, blue: 205 / 255)
    static let slateBackground = Color(red: 20 / 255, green: 20 / 255, blue: 25 / 255)
    static let slateGradientEnd = Color(red: 34 / 255, green: 31 / 255, blue: 45 / 255)
    static let slateText = Color(red: 159 / 255, green: 163 / 255, blue: 172 / 255)
    static let slateAccent = Color(red: 139 / 255, green: 147 / 255, blue: 184 / 255)
    // Midnight: near-black easing into a faint violet, with crisp near-white text.
    static let midnightBackground = Color(red: 10 / 255, green: 10 / 255, blue: 14 / 255)
    static let midnightGradientEnd = Color(red: 27 / 255, green: 21 / 255, blue: 44 / 255)
    static let midnightText = Color(red: 244 / 255, green: 242 / 255, blue: 250 / 255)
    static let midnightAccent = Color(red: 190 / 255, green: 168 / 255, blue: 255 / 255)
    // Kaster brand purple, sampled from the wizard icon. Lighter in dark mode for contrast.
    static let kasterPurple = Color(nsColor: NSColor(name: "KasterPurple") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.71, green: 0.56, blue: 0.94, alpha: 1)
            : NSColor(red: 0.42, green: 0.25, blue: 0.76, alpha: 1)
    })
    // Soft lavender for selected rows and table headers.
    static let kasterSelection = Color(nsColor: NSColor(name: "KasterSelection") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.42, green: 0.30, blue: 0.62, alpha: 0.45)
            : NSColor(red: 0.91, green: 0.87, blue: 0.98, alpha: 1)
    })

    static func background(for stored: String) -> Color {
        if stored == charcoal.rawValue { return charcoalBackground }
        if stored == slate.rawValue { return slateBackground }
        if stored == midnight.rawValue { return midnightBackground }
        return Color(nsColor: .windowBackgroundColor)
    }
    static func backdrop(for stored: String) -> LinearGradient {
        let base = background(for: stored)
        let end = stored == slate.rawValue ? slateGradientEnd : stored == midnight.rawValue ? midnightGradientEnd : base
        return LinearGradient(colors: [base, end],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static func focusAccent(for stored: String, mode: String) -> Color? {
        let light = colorScheme(for: stored) == .light
        switch mode {
        case "habits": return light ? Color(red: 0.20, green: 0.42, blue: 0.34) : Color(red: 0.54, green: 0.73, blue: 0.64)
        case "todos": return light ? Color(red: 0.48, green: 0.32, blue: 0.18) : Color(red: 0.82, green: 0.68, blue: 0.52)
        case "debate": return light ? Color(red: 0.39, green: 0.29, blue: 0.51) : Color(red: 0.70, green: 0.61, blue: 0.82)
        default: return nil
        }
    }
    static func foreground(for stored: String) -> Color? {
        if stored == charcoal.rawValue { return charcoalText }
        if stored == slate.rawValue { return slateText }
        if stored == midnight.rawValue { return midnightText }
        return nil
    }
    // MARK: Custom accent (Settings → Accent color). Empty = the theme's own accent.
    static let accentKey = "kasterAccentHex"

    /// "#6B40C2", "6b40c2" or "#abc" → (r, g, b) in 0…1.
    static func rgb(hex: String) -> (Double, Double, Double)? {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        return (Double((number >> 16) & 0xff) / 255, Double((number >> 8) & 0xff) / 255, Double(number & 0xff) / 255)
    }
    static func hex(of color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(round(srgb.redComponent * 255)), Int(round(srgb.greenComponent * 255)), Int(round(srgb.blueComponent * 255)))
    }
    static var customAccentHex: String? {
        guard let stored = UserDefaults.standard.string(forKey: accentKey), rgb(hex: stored) != nil else { return nil }
        return stored
    }
    static func customAccent() -> Color? {
        guard let hex = customAccentHex, let (r, g, b) = rgb(hex: hex) else { return nil }
        return Color(.sRGB, red: r, green: g, blue: b)
    }
    static func customAccentNSColor() -> NSColor? {
        guard let hex = customAccentHex, let (r, g, b) = rgb(hex: hex) else { return nil }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
    /// The accent in use everywhere: the custom color if set, otherwise Kaster purple.
    static var currentAccent: Color { customAccent() ?? kasterPurple }
    /// Fill for selected rows: a soft wash of the accent.
    static func selectionFill(for stored: String) -> Color {
        if let custom = customAccent() { return custom.opacity(0.2) }
        return foreground(for: stored) == nil ? kasterSelection : (accent(for: stored) ?? kasterPurple).opacity(0.22)
    }

    static func tint(for stored: String) -> Color? {
        if let custom = customAccent() { return custom }
        if stored == charcoal.rawValue { return charcoalBlue }
        if stored == slate.rawValue { return slateAccent }
        if stored == midnight.rawValue { return midnightAccent }
        return kasterPurple
    }
    static func accent(for stored: String) -> Color? { tint(for: stored) }

    // Unknown values use the system appearance, preserving existing installs.
    static func colorScheme(for stored: String) -> ColorScheme? {
        switch AppearancePreference(rawValue: stored) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark, .charcoal, .slate, .midnight: return .dark
        }
    }
}

struct SlatePrimaryButtonStyle: ButtonStyle {
    var midnight = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(midnight ? AppearancePreference.midnightBackground : AppearancePreference.slateBackground)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background((midnight ? AppearancePreference.midnightAccent : AppearancePreference.slateAccent).opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Settings: a small color dot to pick any accent, its hex value, and Reset.
struct AccentColorSetting: View {
    @AppStorage(AppearancePreference.accentKey) private var accentHex = ""
    @State private var field = ""
    @State private var invalid = false

    private var current: Color { AppearancePreference.customAccent() ?? AppearancePreference.kasterPurple }

    var body: some View {
        HStack(spacing: 10) {
            Text("Accent color")
            ColorPicker("Accent color", selection: Binding(
                get: { current },
                set: { color in
                    if let hex = AppearancePreference.hex(of: NSColor(color)) { accentHex = hex; field = hex; invalid = false }
                }), supportsOpacity: false)
                .labelsHidden()
                .help("Pick any accent color")
            TextField("#6B40C2", text: $field)
                .frame(width: 90).font(.system(.body, design: .monospaced))
                .onSubmit(apply)
                .help("Type a hex color such as #2F80ED and press Return")
            if invalid { Text("Use a hex color like #2F80ED").font(.caption).foregroundStyle(.red) }
            Spacer()
            Button("Reset") { accentHex = ""; field = ""; invalid = false }
                .disabled(accentHex.isEmpty)
                .help("Restore the theme's default accent")
        }
        .onAppear { field = accentHex }
    }

    private func apply() {
        let value = field.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { accentHex = ""; invalid = false; return }
        guard let (r, g, b) = AppearancePreference.rgb(hex: value) else { invalid = true; return }
        let normalized = String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
        accentHex = normalized; field = normalized; invalid = false
    }
}

struct AppearanceSettings: View {
    @AppStorage("cardifyAppearance") private var storedAppearance = AppearancePreference.system.rawValue

    var body: some View {
        Picker("Appearance", selection: Binding(get: { AppearancePreference(rawValue: storedAppearance) ?? .system }, set: { storedAppearance = $0.rawValue })) {
            ForEach(AppearancePreference.allCases) { choice in
                Text(choice.title).tag(choice)
            }
        }.pickerStyle(.segmented)
    }
}

struct CharcoalPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(AppearancePreference.charcoalTeal.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct CharcoalPrimaryTint: ViewModifier {
    @AppStorage("cardifyAppearance") private var appearance = AppearancePreference.system.rawValue
    func body(content: Content) -> some View {
        content.tint(appearance == AppearancePreference.charcoal.rawValue ? AppearancePreference.charcoalTeal : AppearancePreference.tint(for: appearance))
    }
}

/// The editor's on-screen text size, as a multiple of the normal size. Printing ignores it.
enum EditorTextScale {
    static let key = "kasterEditorScale"
    static let steps: [Double] = [0.85, 1, 1.15, 1.3, 1.5, 1.75, 2, 2.5]
    static func clamped(_ value: Double) -> CGFloat { CGFloat(min(max(value, steps.first!), steps.last!)) }
    static func bigger(_ value: Double) -> Double { steps.first { $0 > value + 0.001 } ?? steps.last! }
    static func smaller(_ value: Double) -> Double { steps.last { $0 < value - 0.001 } ?? steps.first! }
    static func label(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}
