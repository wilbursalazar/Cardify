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
    static func tint(for stored: String) -> Color? {
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
