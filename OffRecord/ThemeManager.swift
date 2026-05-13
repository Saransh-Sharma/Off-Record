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

    var colorScheme: ColorScheme? {
        .light
    }

    /// Primary accent color for buttons and highlights
    var accentColor: Color {
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
            return OffRecordColor.brandLavender
        }
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
            return OffRecordColor.textInverse
        case .rose, .ocean, .warm:
            return OffRecordColor.textBrand
        }
    }

    /// Secondary color for subtle accents
    var secondaryAccent: Color {
        accentColor.opacity(0.15)
    }

    /// Preview color for theme picker
    var previewColor: Color {
        accentColor
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

    // MARK: - Semantic Colors

    var backgroundColor: Color {
        OffRecordColor.backgroundPrimary
    }

    var textColor: Color {
        OffRecordColor.textPrimary
    }

    var secondaryTextColor: Color {
        OffRecordColor.textSecondary
    }

    var cardBackgroundColor: Color {
        OffRecordColor.surfacePrimary
    }

    /// Theme-aware accent color for UI elements
    var accentColor: Color {
        selectedTheme.accentColor
    }

    var readableAccentColor: Color {
        selectedTheme.readableAccentColor
    }

    /// Data visualization color (charts, meters, bars)
    var dataColor: Color {
        OffRecordColor.brandAqua
    }

    var elevatedCardBackgroundColor: Color {
        OffRecordColor.surfaceWarm
    }

    var borderColor: Color {
        OffRecordColor.borderSoft
    }

    var privacyColor: Color {
        OffRecordColor.brandSageDark
    }

    var fridayColor: Color {
        OffRecordColor.brandLavenderDark
    }

    var journalColor: Color {
        OffRecordColor.brandPeach
    }

    var exportColor: Color {
        OffRecordColor.brandSky
    }

    var warningColor: Color {
        OffRecordColor.brandCoral
    }
}
