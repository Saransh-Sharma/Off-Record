//
//  OffRecordDesignTokens.swift
//  OffRecord
//
//  Pastel design tokens derived from OffRecord Design.md.
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
    static let backgroundSecondary = Color(hex: 0xF7F1EA)
    static let backgroundLavenderTint = Color(hex: 0xF4EEFF)
    static let backgroundBlushTint = Color(hex: 0xFFF0F3)
    static let backgroundSageTint = Color(hex: 0xEEF6EF)
    static let backgroundPeachTint = Color(hex: 0xFFF1E5)
    static let backgroundSkyTint = Color(hex: 0xEEF8FF)
    static let backgroundElevated = Color(hex: 0xFFFFFF)

    static let surfacePrimary = Color(hex: 0xFFFFFF)
    static let surfaceWarm = Color(hex: 0xFFFBF7)
    static let surfacePeach = Color(hex: 0xFFF1E5)
    static let surfaceBlush = Color(hex: 0xFFF0F3)
    static let surfaceLavender = Color(hex: 0xF4EEFF)
    static let surfaceSage = Color(hex: 0xEEF6EF)
    static let surfaceMint = Color(hex: 0xEFFAF4)
    static let surfaceBlue = Color(hex: 0xEEF8FF)

    static let textPrimary = Color(hex: 0x18131D)
    static let textHeading = Color(hex: 0x241730)
    static let textBrand = Color(hex: 0x342044)
    static let textSecondary = Color(hex: 0x716A75)
    static let textTertiary = Color(hex: 0x9B949E)
    static let textInverse = Color(hex: 0xFFFFFF)
    static let textSage = Color(hex: 0x5F806B)
    static let textWarm = Color(hex: 0xC97836)

    // Readable semantic foregrounds for pastel accents. The brand colors remain
    // soft fills; these aliases are for text and small symbols on light surfaces.
    static let textAqua = Color(hex: 0x2D7168)
    static let textBlush = Color(hex: 0x9B4357)
    static let textCoral = Color(hex: 0x9F4036)
    static let textLavender = brandLavenderDark
    static let textMint = Color(hex: 0x4C775B)
    static let textPeach = Color(hex: 0x8D4F1E)
    static let textSky = Color(hex: 0x386C84)
    static let textYellow = Color(hex: 0x735F1E)

    static let borderSoft = Color(hex: 0xEEE7EF)
    static let borderWarm = Color(hex: 0xF2E2D5)
    static let borderSage = Color(hex: 0xD8E6DC)
    static let divider = Color(hex: 0xE8E1E8)
    static let hairline = Color(hex: 0xF0ECF1)

    static let moodGreat = Color(hex: 0xA8D8BE)
    static let moodGood = Color(hex: 0x7FA08A)
    static let moodCalm = Color(hex: 0x6FC6B8)
    static let moodOkay = Color(hex: 0xF7D98B)
    static let moodTired = Color(hex: 0xF6B98F)
    static let moodSad = Color(hex: 0xF6A9B8)
    static let moodAnxious = Color(hex: 0xBBA7E8)
    static let moodAngry = Color(hex: 0xEF8A7A)

    static let darkBackground = Color(hex: 0x18131D)
    static let darkSurface = Color(hex: 0x241730)
    static let darkSurfaceElevated = Color(hex: 0x342044)

    static let appBackgroundGradient = LinearGradient(
        colors: [backgroundPrimary, Color(hex: 0xF8F1F7), Color(hex: 0xF3F6EF)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let todayCaptureGradient = LinearGradient(
        colors: [Color(hex: 0xFFE3DD), Color(hex: 0xF6E8FF)],
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

enum OffRecordSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let section: CGFloat = 40
    static let screenX: CGFloat = 24
    static let screenY: CGFloat = 28
}

enum OffRecordRadius {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 34
}

enum OffRecordTypography {
    static let displayXL = Font.system(size: 52, weight: .bold, design: .serif)
    static let screenTitle = Font.system(size: 40, weight: .heavy, design: .default)
    static let titleLarge = Font.system(size: 28, weight: .bold, design: .default)
    static let titleMedium = Font.system(size: 22, weight: .bold, design: .default)
    static let bodyLarge = Font.system(size: 17, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 15, weight: .regular, design: .default)
    static let bodySmall = Font.system(size: 13, weight: .regular, design: .default)
    static let labelMedium = Font.system(size: 13, weight: .semibold, design: .default)
    static let labelSmall = Font.system(size: 11, weight: .semibold, design: .default)
    static let numberLarge = Font.system(size: 44, weight: .heavy, design: .rounded)
}

enum OffRecordShadow {
    static let cardColor = Color.black.opacity(0.06)
    static let floatingColor = Color.black.opacity(0.08)
    static let tabColor = Color.black.opacity(0.10)
}

struct OffRecordReadableTintStyle {
    let tint: Color?
    let fill: Color
    let foreground: Color
    let border: Color

    static let neutral = OffRecordReadableTintStyle(
        tint: nil,
        fill: OffRecordColor.surfaceWarm,
        foreground: OffRecordColor.textBrand,
        border: OffRecordColor.borderSoft
    )

    static let brand = OffRecordReadableTintStyle(
        tint: OffRecordColor.brandPlum,
        fill: OffRecordColor.surfaceLavender,
        foreground: OffRecordColor.textBrand,
        border: OffRecordColor.borderSoft
    )

    static let privacy = OffRecordReadableTintStyle(
        tint: OffRecordColor.brandSageDark,
        fill: OffRecordColor.backgroundSageTint,
        foreground: OffRecordColor.textSage,
        border: OffRecordColor.borderSage
    )

    static let friday = OffRecordReadableTintStyle(
        tint: OffRecordColor.brandLavenderDark,
        fill: OffRecordColor.backgroundLavenderTint,
        foreground: OffRecordColor.textLavender,
        border: OffRecordColor.borderSoft
    )

    static let journal = OffRecordReadableTintStyle(
        tint: OffRecordColor.brandPeach,
        fill: OffRecordColor.backgroundPeachTint,
        foreground: OffRecordColor.textPeach,
        border: OffRecordColor.borderWarm
    )

    static let blush = OffRecordReadableTintStyle(
        tint: OffRecordColor.brandBlush,
        fill: OffRecordColor.backgroundBlushTint,
        foreground: OffRecordColor.textBlush,
        border: OffRecordColor.borderSoft
    )

    static let growth = OffRecordReadableTintStyle(
        tint: OffRecordColor.brandAqua,
        fill: OffRecordColor.surfaceMint,
        foreground: OffRecordColor.textAqua,
        border: OffRecordColor.borderSage
    )

    static let export = OffRecordReadableTintStyle(
        tint: OffRecordColor.brandSky,
        fill: OffRecordColor.backgroundSkyTint,
        foreground: OffRecordColor.textSky,
        border: OffRecordColor.borderSoft
    )

    static let highlight = OffRecordReadableTintStyle(
        tint: OffRecordColor.brandYellow,
        fill: OffRecordColor.surfacePeach,
        foreground: OffRecordColor.textYellow,
        border: OffRecordColor.borderWarm
    )

    static let warning = OffRecordReadableTintStyle(
        tint: OffRecordColor.brandCoral,
        fill: OffRecordColor.backgroundBlushTint,
        foreground: OffRecordColor.textCoral,
        border: OffRecordColor.borderWarm
    )
}

struct OffRecordCardModifier: ViewModifier {
    var cornerRadius: CGFloat = OffRecordRadius.xl
    var fill: Color = OffRecordColor.surfacePrimary
    var border: Color = OffRecordColor.borderSoft
    var shadow: Bool = true

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(border, lineWidth: 1)
                    )
                    .shadow(color: shadow ? OffRecordShadow.cardColor : .clear, radius: 18, x: 0, y: 8)
            )
    }
}

struct OffRecordPillButtonModifier: ViewModifier {
    var fill: Color = OffRecordColor.brandPlum
    var foreground: Color = OffRecordColor.textInverse

    func body(content: Content) -> some View {
        content
            .font(OffRecordTypography.labelMedium)
            .foregroundStyle(foreground)
            .frame(minHeight: 52)
            .padding(.horizontal, OffRecordSpacing.lg)
            .background(fill, in: Capsule())
    }
}

extension View {
    func offRecordCard(
        cornerRadius: CGFloat = OffRecordRadius.xl,
        fill: Color = OffRecordColor.surfacePrimary,
        border: Color = OffRecordColor.borderSoft,
        shadow: Bool = true
    ) -> some View {
        modifier(OffRecordCardModifier(cornerRadius: cornerRadius, fill: fill, border: border, shadow: shadow))
    }

    func offRecordPillButton(
        fill: Color = OffRecordColor.brandPlum,
        foreground: Color = OffRecordColor.textInverse
    ) -> some View {
        modifier(OffRecordPillButtonModifier(fill: fill, foreground: foreground))
    }

    func offRecordScreenBackground() -> some View {
        background(OffRecordColor.appBackgroundGradient.ignoresSafeArea())
    }

    func offRecordReadablePill(
        _ style: OffRecordReadableTintStyle,
        horizontalPadding: CGFloat = 12,
        verticalPadding: CGFloat = 8
    ) -> some View {
        font(OffRecordTypography.labelMedium)
            .foregroundStyle(style.foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(style.fill, in: Capsule())
            .overlay(Capsule().stroke(style.border, lineWidth: 1))
    }
}

struct OffRecordPrivacyBadge: View {
    var compact = false
    var title = "Private"
    var subtitle: String?

    var body: some View {
        HStack(spacing: compact ? 5 : 8) {
            Image(systemName: "lock.shield.fill")
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(OffRecordColor.brandSageDark)

            if !compact {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(OffRecordTypography.labelSmall)
                        .foregroundStyle(OffRecordColor.textSage)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(OffRecordColor.textSecondary)
                    }
                }
            }
        }
        .padding(.horizontal, compact ? 9 : 12)
        .padding(.vertical, compact ? 5 : 8)
        .background(OffRecordColor.backgroundSageTint, in: Capsule())
        .overlay(Capsule().stroke(OffRecordColor.borderSage, lineWidth: 1))
    }
}

struct OffRecordIconBubble: View {
    let systemImage: String
    var tint: Color = OffRecordColor.brandLavenderDark
    var fill: Color? = nil
    var size: CGFloat = 40
    var iconSize: CGFloat = 16

    var body: some View {
        ZStack {
            Circle()
                .fill(fill ?? tint.opacity(0.14))
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}
