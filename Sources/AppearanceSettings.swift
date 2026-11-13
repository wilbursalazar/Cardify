import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    // Unknown values use the system appearance, preserving existing installs.
    static func colorScheme(for stored: String) -> ColorScheme? {
        switch AppearancePreference(rawValue: stored) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
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
