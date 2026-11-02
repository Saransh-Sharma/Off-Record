//
//  OffRecordColor.swift
//  OffRecordSystemShared
//
//  The color tokens from OffRecord Design.md, shared by the app and the
//  widget extension so both draw from one palette. Spacing, typography, and
//  other app-only tokens stay in OffRecord/OffRecordDesignTokens.swift; the
//  widget's own typography and background stay in
//  OffRecordWidget/OffRecordDesignTokens.swift.
//

import SwiftUI
import UIKit

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
}

extension Color {
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
    static let backgroundSecondary = Color(light: 0xF7F1EA, dark: 0x1D1723)
    static let backgroundLavenderTint = Color(light: 0xF4EEFF, dark: 0x281F36)
    static let backgroundBlushTint = Color(light: 0xFFF0F3, dark: 0x30202A)
    static let backgroundSageTint = Color(light: 0xEEF6EF, dark: 0x1C2922)
    static let backgroundPeachTint = Color(light: 0xFFF1E5, dark: 0x2F241C)
    static let backgroundSkyTint = Color(light: 0xEEF8FF, dark: 0x1B2630)
    static let backgroundElevated = Color(light: 0xFFFFFF, dark: 0x241D2B)

    static let surfacePrimary = Color(light: 0xFFFFFF, dark: 0x211A28)
    static let surfaceWarm = Color(light: 0xFFFBF7, dark: 0x251E2C)
    static let surfacePeach = Color(light: 0xFFF1E5, dark: 0x2F241C)
    static let surfaceBlush = Color(light: 0xFFF0F3, dark: 0x30202A)
    static let surfaceLavender = Color(light: 0xF4EEFF, dark: 0x281F36)
    static let surfaceSage = Color(light: 0xEEF6EF, dark: 0x1C2922)
    static let surfaceMint = Color(light: 0xEFFAF4, dark: 0x1B2A24)
    static let surfaceBlue = Color(light: 0xEEF8FF, dark: 0x1B2630)

    static let textPrimary = Color(light: 0x18131D, dark: 0xF3EDF5)
    static let textHeading = Color(light: 0x241730, dark: 0xF7F1FA)
    static let textBrand = Color(light: 0x342044, dark: 0xE4D6F2)
    static let textSecondary = Color(light: 0x716A75, dark: 0xB5ACBA)
    static let textSecondaryDark = Color(hex: 0xA8A0AC)
    static let textOnTinted = Color(light: 0x554E58, dark: 0xCBC2CF)
    static let textTertiary = Color(light: 0x9B949E, dark: 0x8D8592)
    static let textInverse = Color(hex: 0xFFFFFF)
    /// White foreground for saturated accent fills (plum, lavender-dark, sage-dark) in both appearances.
    static let textOnAccent = Color.white
    /// Rim highlight for glass controls: bright on light surfaces, subdued on dark.
    static let glassRim = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.14) : UIColor.white.withAlphaComponent(0.58)
    })
    static let textSage = Color(light: 0x5F806B, dark: 0x9DC6A9)
    static let textWarm = Color(light: 0xC97836, dark: 0xEAA66B)

    // Readable semantic foregrounds for pastel accents. The brand colors remain
    // soft fills; these aliases are for text and small symbols on light surfaces.
    static let textAqua = Color(light: 0x2D7168, dark: 0x84D4C7)
    static let textBlush = Color(light: 0x9B4357, dark: 0xF2A7B8)
    static let textCoral = Color(light: 0x9F4036, dark: 0xF4A294)
    static let textLavender = Color(light: 0x7B5CAF, dark: 0xC7B2F2)
    static let textMint = Color(light: 0x4C775B, dark: 0x9FD1B0)
    static let textPeach = Color(light: 0x8D4F1E, dark: 0xF1BA8D)
    static let textSky = Color(light: 0x386C84, dark: 0x9FCFE7)
    static let textYellow = Color(light: 0x735F1E, dark: 0xEBD38B)

    static let borderSoft = Color(light: 0xEEE7EF, dark: 0x3A3143)
    static let borderWarm = Color(light: 0xF2E2D5, dark: 0x40342A)
    static let borderSage = Color(light: 0xD8E6DC, dark: 0x2F4137)
    static let borderDark = Color(hex: 0x4A3A5A)
    static let divider = Color(light: 0xE8E1E8, dark: 0x352C3E)
    static let hairline = Color(light: 0xF0ECF1, dark: 0x2B2432)

    static let moodGreat = pastelMint
    static let moodGood = pastelSage
    static let moodCalm = pastelAqua
    static let moodOkay = pastelYellow
    static let moodTired = pastelPeach
    static let moodSad = pastelBlush
    static let moodAnxious = pastelLavender
    static let moodAngry = pastelCoral

    static let darkBackground = Color(hex: 0x18131D)
    static let darkSurface = Color(hex: 0x241730)
    static let darkSurfaceElevated = Color(hex: 0x342044)

    // Widget surfaces: the Live Activity, record glyphs, and the year-in-pixels grid.
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

    static let todayCaptureGradient = LinearGradient(
        colors: [Color(light: 0xFFE3DD, dark: 0x3A2430), Color(light: 0xF6E8FF, dark: 0x2D2340)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let fridayGradient = LinearGradient(
        colors: [brandLavender, Color(hex: 0xD8A6D9)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let insightGradient = LinearGradient(
        colors: [backgroundLavenderTint, backgroundPrimary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
