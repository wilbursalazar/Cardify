import AppKit
import SwiftUI

precondition(AppearancePreference.colorScheme(for: "system") == nil)
precondition(AppearancePreference.colorScheme(for: "") == nil)
precondition(AppearancePreference.colorScheme(for: "unrecognized") == nil)
precondition(AppearancePreference.colorScheme(for: "light") == .light)
precondition(AppearancePreference.colorScheme(for: "dark") == .dark)
precondition(AppearancePreference.colorScheme(for: "charcoal") == .dark)
precondition(AppearancePreference.colorScheme(for: "slate") == .dark)
precondition(AppearancePreference.allCases.map(\.title) == ["System", "Light", "Dark", "Charcoal", "Slate"])
precondition(AppearancePreference.tint(for: "light") == nil)
precondition(AppearancePreference.accent(for: "dark") == nil)
precondition(AppearancePreference.tint(for: "charcoal") == AppearancePreference.charcoalBlue)
precondition(AppearancePreference.accent(for: "charcoal") == AppearancePreference.charcoalBlue)

func luminance(_ color: Color) -> Double {
    let rgb = NSColor(color).usingColorSpace(.sRGB)!
    func linear(_ channel: CGFloat) -> Double {
        let value = Double(channel)
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
}
func contrast(_ a: Color, _ b: Color) -> Double {
    let values = [luminance(a), luminance(b)].sorted()
    return (values[1] + 0.05) / (values[0] + 0.05)
}
precondition(contrast(AppearancePreference.charcoalText, AppearancePreference.charcoalBackground) >= 4.5)
precondition(contrast(AppearancePreference.charcoalBlue, AppearancePreference.charcoalBackground) >= 4.5)
precondition(contrast(.white, AppearancePreference.charcoalTeal) >= 4.5)
precondition(AppearancePreference.tint(for: "slate") == AppearancePreference.slateAccent)
precondition(contrast(AppearancePreference.slateText, AppearancePreference.slateBackground) >= 4.5)
precondition(contrast(AppearancePreference.slateAccent, AppearancePreference.slateBackground) >= 4.5)
precondition(AppearancePreference.focusAccent(for: "slate", mode: "markdown") == nil)
for mode in ["habits", "todos", "debate"] {
    let dark = AppearancePreference.focusAccent(for: "slate", mode: mode)!
    let light = AppearancePreference.focusAccent(for: "light", mode: mode)!
    precondition(contrast(dark, AppearancePreference.slateGradientEnd) >= 4.5)
    precondition(contrast(light, .white) >= 4.5)
}
_ = AppearancePreference.backdrop(for: "slate")
print("Appearance preferences and Charcoal palette contrast passed")
