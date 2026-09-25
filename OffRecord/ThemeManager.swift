//
//  ThemeManager.swift
//  OffRecord
//
//  Manages app appearance themes with soft, clean color palettes.
//

import SwiftUI

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case sage = "Sage"
    case lavender = "Lavender"
    case rose = "Rose"
    case ocean = "Ocean"
    case warm = "Warm"
    case dark = "Dark"

    var id: String { rawValue }

    /// Display icon for theme picker
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .sage: return "leaf"
        case .lavender: return "sparkles"
        case .rose: return "heart"
        case .ocean: return "drop"
        case .warm: return "flame"
        case .dark: return "moon.stars"
        }
    }

    /// `nil` follows the device appearance. Only Light and Dark force a scheme;
    /// accent themes (Sage, Lavender, …) adapt to the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        default: return nil
        }
    }

    /// Global tint for system controls. Uses readable accents so pastel themes
    /// never produce low-contrast toggles, links, or button labels.
    var accentColor: Color {
        readableAccentColor
    }

    /// Soft fill color used for theme swatches and decorative accents.
    var swatchColor: Color {
        switch self {
        case .system, .light:
            return OffRecordColor.brandPlum
        case .sage:
            return OffRecordColor.brandSageDark
        case .lavender:
            return OffRecordColor.brandLavenderDark
        case .rose:
            return OffRecordColor.brandBlush
        case .ocean:
            return OffRecordColor.brandAqua
        case .warm:
            return OffRecordColor.brandPeach
        case .dark:
            return OffRecordColor.darkSurfaceElevated
        }
    }

    /// Screen background wash for this theme, adapting to light and dark appearance.
    var backgroundGradient: LinearGradient {
        let stops: [Color]
        switch self {
        case .system, .light, .dark:
            return OffRecordColor.appBackgroundGradient
        case .sage:
            stops = [Color(light: 0xF6F8F1, dark: 0x141A16), Color(light: 0xEEF6EF, dark: 0x18211C), Color(light: 0xF8F4EA, dark: 0x161A17)]
        case .lavender:
            stops = [Color(light: 0xF9F4FF, dark: 0x1A1424), Color(light: 0xF4EEFF, dark: 0x221A30), Color(light: 0xFFF8F0, dark: 0x16111B)]
        case .rose:
            stops = [Color(light: 0xFFF6F5, dark: 0x1D1418), Color(light: 0xFFF0F3, dark: 0x261A20), Color(light: 0xFFF8F0, dark: 0x16111B)]
        case .ocean:
            stops = [Color(light: 0xF2FAFA, dark: 0x121A1E), Color(light: 0xEEF8FF, dark: 0x162229), Color(light: 0xF3F6EF, dark: 0x151A17)]
        case .warm:
            stops = [Color(light: 0xFFF7EC, dark: 0x1C1611), Color(light: 0xFFF1E5, dark: 0x241B14), Color(light: 0xFFF8F0, dark: 0x16111B)]
        }
        return LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Text-safe version of the theme accent. Pastel brand colors are fills,
    /// not foreground colors, per OffRecord Design.md.
    var readableAccentColor: Color {
        switch self {
        case .system, .light, .dark:
            return OffRecordColor.textBrand
        case .sage:
            return OffRecordColor.textSage
        case .lavender:
            return OffRecordColor.textLavender
        case .rose:
            return OffRecordColor.textBlush
        case .ocean:
            return OffRecordColor.textAqua
        case .warm:
            return OffRecordColor.textPeach
        }
    }

    var swatchForegroundColor: Color {
        switch self {
        case .system, .light, .sage, .lavender, .dark:
            return OffRecordColor.textOnAccent
        case .rose, .ocean, .warm:
            return Color(hex: 0x342044)
        }
    }

    /// Preview color for theme picker
    var previewColor: Color {
        swatchColor
    }
}

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private let defaults = UserDefaults.standard
    private let themeKey = "selectedTheme"

    @Published var selectedTheme: AppTheme {
        didSet {
            defaults.set(selectedTheme.rawValue, forKey: themeKey)
        }
    }

    private init() {
        let saved = defaults.string(forKey: themeKey) ?? AppTheme.system.rawValue
        self.selectedTheme = AppTheme(rawValue: saved) ?? .system
    }

    var accentColor: Color {
        selectedTheme.accentColor
    }

    var readableAccentColor: Color {
        selectedTheme.readableAccentColor
    }
}

// MARK: - Themed background

/// The app's screen background. Observes the selected theme so every screen
/// picks up theme changes live, and adapts to light/dark appearance.
struct OffRecordAppBackground: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        themeManager.selectedTheme.backgroundGradient
    }
}
