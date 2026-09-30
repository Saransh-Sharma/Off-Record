//
//  OffRecordDesignTokens.swift
//  OffRecordWidget
//
//  CANONICAL SOURCE: OffRecord/OffRecordDesignTokens.swift
//  Keep color values in sync with the main app target.
//  Widget-only additions (OffRecordWidgetBackground, OffRecordWidgetTypography,
//  pixel colors) remain here.
//

import SwiftUI
import UIKit
import WidgetKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// A color that resolves per trait collection so tokens adapt to light and dark appearances.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

enum OffRecordColor {
    static let brandPlum = Color(light: 0x342044, dark: 0x6E4F9E)
    static let pastelMint = Color(hex: 0xA8D8BE)
    static let pastelSage = Color(hex: 0x7FA08A)
    static let pastelAqua = Color(hex: 0x6FC6B8)
    static let pastelYellow = Color(hex: 0xF7D98B)
    static let pastelPeach = Color(hex: 0xF6B98F)
    static let pastelBlush = Color(hex: 0xF6A9B8)
    static let pastelLavender = Color(hex: 0xBBA7E8)
    static let pastelCoral = Color(hex: 0xEF8A7A)

    static let brandSage = pastelSage
    static let brandSageDark = Color(hex: 0x5F806B)
    static let brandLavender = pastelLavender
    static let brandLavenderDark = Color(hex: 0x7B5CAF)
    static let brandPeach = pastelPeach
    static let brandBlush = pastelBlush
    static let brandMint = pastelMint
    static let brandAqua = pastelAqua
    static let brandSky = Color(hex: 0xA8D6F0)
    static let brandYellow = pastelYellow
    static let brandCoral = pastelCoral

    static let backgroundPrimary = Color(light: 0xFFF8F0, dark: 0x16111B)
    static let backgroundPeachTint = Color(light: 0xFFF1E5, dark: 0x2F241C)
    static let backgroundSageTint = Color(light: 0xEEF6EF, dark: 0x1C2922)
    static let backgroundLavenderTint = Color(light: 0xF4EEFF, dark: 0x281F36)
    static let surfacePrimary = Color(light: 0xFFFFFF, dark: 0x211A28)
    static let surfaceWarm = Color(light: 0xFFFBF7, dark: 0x251E2C)
    static let surfaceLavender = Color(light: 0xF4EEFF, dark: 0x281F36)
    static let textPrimary = Color(light: 0x18131D, dark: 0xF3EDF5)
    static let textHeading = Color(light: 0x241730, dark: 0xF7F1FA)
    static let textBrand = Color(light: 0x342044, dark: 0xE4D6F2)
    static let textSecondary = Color(light: 0x716A75, dark: 0xB5ACBA)
    static let textOnTinted = Color(light: 0x554E58, dark: 0xCBC2CF)
    static let textInverse = Color(hex: 0xFFFFFF)
    static let textOnAccent = Color.white
    static let textAqua = Color(light: 0x2D7168, dark: 0x84D4C7)
    static let textBlush = Color(light: 0x9B4357, dark: 0xF2A7B8)
    static let textCoral = Color(light: 0x9F4036, dark: 0xF4A294)
    static let textLavender = Color(light: 0x7B5CAF, dark: 0xC7B2F2)
    static let textMint = Color(light: 0x4C775B, dark: 0x9FD1B0)
    static let textPeach = Color(light: 0x8D4F1E, dark: 0xF1BA8D)
    static let textSage = Color(light: 0x5F806B, dark: 0x9DC6A9)
    static let textYellow = Color(light: 0x735F1E, dark: 0xEBD38B)
    static let textWarm = Color(light: 0xC97836, dark: 0xEAA66B)
    static let borderSoft = Color(light: 0xEEE7EF, dark: 0x3A3143)
    static let moodGreat = pastelMint
    static let moodGood = pastelSage
    static let moodCalm = pastelAqua
    static let moodOkay = pastelYellow
    static let moodTired = pastelPeach
    static let moodSad = pastelBlush
    static let moodAnxious = pastelLavender
    static let moodAngry = pastelCoral

    /// Recording red for the Live Activity and record glyphs.
    static let recording = Color(hex: 0xF0605A)
    /// Plum fill for the primary record action; stays saturated in both appearances.
    static let recordFill = Color(light: 0x342044, dark: 0x6E4F9E)

    /// Year-in-pixels: a day with no entry.
    static let pixelEmpty = Color(light: 0xEEE7EF, dark: 0x2E2636)
    /// Year-in-pixels: a day with an entry but no mood.
    static let pixelNeutral = Color(light: 0xCFC6D3, dark: 0x5A4F63)

    static let appBackgroundGradient = LinearGradient(
        colors: [backgroundPrimary, Color(light: 0xF8F1F7, dark: 0x1A1420), Color(light: 0xF3F6EF, dark: 0x151A17)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Widget-Only Modifiers

struct OffRecordWidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            OffRecordColor.appBackgroundGradient
        }
    }
}

extension View {
    func offRecordWidgetBackground() -> some View {
        modifier(OffRecordWidgetBackground())
    }
}

enum OffRecordWidgetTypography {
    static let titleLarge = Font.system(.title, design: .rounded, weight: .bold)
    static let titleMedium = Font.system(.title2, design: .rounded, weight: .bold)
    static let titleSmall = Font.system(.title3, design: .rounded, weight: .bold)
    static let cardTitle = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.system(.callout, design: .default, weight: .regular)
    static let bodySmall = Font.system(.subheadline, design: .default, weight: .regular)
    static let label = Font.system(.footnote, design: .default, weight: .semibold)
    static let eyebrow = Font.system(.caption, design: .rounded, weight: .semibold)
    static let metadata = Font.system(.caption, design: .default, weight: .regular)
    static let micro = Font.system(.caption2, design: .default, weight: .medium)
    static let numberLarge = Font.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()
    static let numberMedium = Font.system(.title2, design: .rounded, weight: .bold).monospacedDigit()
    static let numberSmall = Font.system(.headline, design: .rounded, weight: .semibold).monospacedDigit()
}
