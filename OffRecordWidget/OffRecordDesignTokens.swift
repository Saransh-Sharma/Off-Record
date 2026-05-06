//
//  OffRecordDesignTokens.swift
//  OffRecordWidget
//
//  Widget-safe pastel design tokens derived from OffRecord Design.md.
//

import SwiftUI

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

enum OffRecordColor {
    static let brandPlum = Color(hex: 0x342044)
    static let brandSage = Color(hex: 0x7FA08A)
    static let brandSageDark = Color(hex: 0x5F806B)
    static let brandLavender = Color(hex: 0xBBA7E8)
    static let brandLavenderDark = Color(hex: 0x7B5CAF)
    static let brandPeach = Color(hex: 0xF6B98F)
    static let brandBlush = Color(hex: 0xF6A9B8)
    static let brandMint = Color(hex: 0xA8D8BE)
    static let brandAqua = Color(hex: 0x6FC6B8)
    static let brandSky = Color(hex: 0xA8D6F0)
    static let brandYellow = Color(hex: 0xF7D98B)
    static let brandCoral = Color(hex: 0xEF8A7A)

    static let backgroundPrimary = Color(hex: 0xFFF8F0)
    static let backgroundPeachTint = Color(hex: 0xFFF1E5)
    static let backgroundSageTint = Color(hex: 0xEEF6EF)
    static let backgroundLavenderTint = Color(hex: 0xF4EEFF)
    static let surfacePrimary = Color(hex: 0xFFFFFF)
    static let surfaceWarm = Color(hex: 0xFFFBF7)
    static let textPrimary = Color(hex: 0x18131D)
    static let textHeading = Color(hex: 0x241730)
    static let textBrand = Color(hex: 0x342044)
    static let textSecondary = Color(hex: 0x716A75)
    static let textInverse = Color(hex: 0xFFFFFF)
    static let textAqua = Color(hex: 0x2D7168)
    static let textBlush = Color(hex: 0x9B4357)
    static let textCoral = Color(hex: 0x9F4036)
    static let textLavender = brandLavenderDark
    static let textMint = Color(hex: 0x4C775B)
    static let textPeach = Color(hex: 0x8D4F1E)
    static let textSage = Color(hex: 0x5F806B)
    static let textYellow = Color(hex: 0x735F1E)
    static let borderSoft = Color(hex: 0xEEE7EF)
    static let moodGreat = Color(hex: 0xA8D8BE)
    static let moodGood = Color(hex: 0x7FA08A)
    static let moodCalm = Color(hex: 0x6FC6B8)
    static let moodOkay = Color(hex: 0xF7D98B)
    static let moodTired = Color(hex: 0xF6B98F)
    static let moodSad = Color(hex: 0xF6A9B8)
    static let moodAnxious = Color(hex: 0xBBA7E8)
    static let moodAngry = Color(hex: 0xEF8A7A)

    static let appBackgroundGradient = LinearGradient(
        colors: [backgroundPrimary, Color(hex: 0xF8F1F7), Color(hex: 0xF3F6EF)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct OffRecordWidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                OffRecordColor.appBackgroundGradient
            }
        } else {
            content.background(OffRecordColor.backgroundPrimary)
        }
    }
}

extension View {
    func offRecordWidgetBackground() -> some View {
        modifier(OffRecordWidgetBackground())
    }
}
