import SwiftUI

precondition(AppearancePreference.colorScheme(for: "system") == nil)
precondition(AppearancePreference.colorScheme(for: "") == nil)
precondition(AppearancePreference.colorScheme(for: "unrecognized") == nil)
precondition(AppearancePreference.colorScheme(for: "light") == .light)
precondition(AppearancePreference.colorScheme(for: "dark") == .dark)
precondition(AppearancePreference.allCases.map(\.title) == ["System", "Light", "Dark"])
print("System, Light, Dark, and unknown appearance preferences passed")
