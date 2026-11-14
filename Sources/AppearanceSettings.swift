import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case charcoal

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    static let charcoalBackground = Color(red: 28 / 255, green: 27 / 255, blue: 35 / 255)
    static let charcoalText = Color(red: 202 / 255, green: 200 / 255, blue: 182 / 255)
    static let charcoalTeal = Color(red: 6 / 255, green: 126 / 255, blue: 137 / 255)
    static let charcoalBlue = Color(red: 148 / 255, green: 180 / 255, blue: 205 / 255)

    static func background(for stored: String) -> Color {
        stored == charcoal.rawValue ? charcoalBackground : Color(nsColor: .windowBackgroundColor)
    }
    static func tint(for stored: String) -> Color? { stored == charcoal.rawValue ? charcoalBlue : nil }
    static func accent(for stored: String) -> Color? { stored == charcoal.rawValue ? charcoalBlue : nil }

    // Unknown values use the system appearance, preserving existing installs.
    static func colorScheme(for stored: String) -> ColorScheme? {
        switch AppearancePreference(rawValue: stored) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark, .charcoal: return .dark
        }
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
        content.tint(appearance == AppearancePreference.charcoal.rawValue ? AppearancePreference.charcoalTeal : nil)
    }
}
