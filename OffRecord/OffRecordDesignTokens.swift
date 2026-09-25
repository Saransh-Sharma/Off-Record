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
    static let displayXL = Font.system(.largeTitle, design: .serif, weight: .bold)
    static let screenTitle = Font.system(.largeTitle, design: .default, weight: .heavy)
    static let titleLarge = Font.system(.title, design: .default, weight: .bold)
    static let titleMedium = Font.system(.title2, design: .default, weight: .bold)
    static let titleSmall = Font.system(.title3, design: .default, weight: .semibold)
    static let sectionTitle = Font.system(.headline, design: .default, weight: .semibold)
    static let cardTitle = Font.system(.headline, design: .default, weight: .semibold)
    static let bodyLarge = Font.system(.body, design: .default, weight: .regular)
    static let journalBody = Font.system(.body, design: .default, weight: .regular).leading(.loose)
    static let bodyMedium = Font.system(.callout, design: .default, weight: .regular)
    static let bodySmall = Font.system(.subheadline, design: .default, weight: .regular)
    static let labelLarge = Font.system(.callout, design: .default, weight: .semibold)
    static let labelMedium = Font.system(.subheadline, design: .default, weight: .semibold)
    static let labelSmall = Font.system(.footnote, design: .default, weight: .semibold)
    static let metadata = Font.system(.footnote, design: .default, weight: .regular)
    static let annotation = Font.system(.caption, design: .default, weight: .regular)
    static let badgeLabel = Font.system(.footnote, design: .rounded, weight: .semibold)
    static let numberLarge = Font.system(.largeTitle, design: .rounded, weight: .heavy).monospacedDigit()
    static let numberMedium = Font.system(.title2, design: .rounded, weight: .bold).monospacedDigit()
    static let numberSmall = Font.system(.headline, design: .rounded, weight: .semibold).monospacedDigit()
}

enum OffRecordExportTypography {
    static let brand = Font.system(size: 14, weight: .bold, design: .rounded)
    static let eyebrow = Font.system(size: 13, weight: .heavy, design: .rounded)
    static let headline = Font.system(size: 22, weight: .bold, design: .default)
    static let body = Font.system(size: 15, weight: .regular, design: .default)
    static let label = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let metadata = Font.system(size: 12, weight: .medium, design: .default)
    static let micro = Font.system(size: 10, weight: .medium, design: .default)
    static let monospaced = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let microMonospaced = Font.system(size: 10, weight: .medium, design: .monospaced)
}

enum OffRecordShadow {
    static let cardColor = Color.black.opacity(0.06)
    static let floatingColor = Color.black.opacity(0.08)
    static let tabColor = Color.black.opacity(0.10)
}

/// Soft paper-like elevation levels from OffRecord Design.md § Elevation & Depth.
enum OffRecordElevation {
    case none
    case chip
    case card
    case floating
    case bar

    var color: Color {
        switch self {
        case .none: return .clear
        case .chip: return Color.black.opacity(0.04)
        case .card: return OffRecordShadow.cardColor
        case .floating: return OffRecordShadow.floatingColor
        case .bar: return OffRecordShadow.tabColor
        }
    }

    var radius: CGFloat {
        switch self {
        case .none: return 0
        case .chip: return 6
        case .card: return 18
        case .floating: return 24
        case .bar: return 30
        }
    }

    var y: CGFloat {
        switch self {
        case .none: return 0
        case .chip: return 2
        case .card: return 8
        case .floating: return 10
        case .bar: return 8
        }
    }
}

/// Shared motion vocabulary. Route animations through these so Reduce Motion is honored consistently.
enum OffRecordMotion {
    /// Quick UI feedback: toggles, chips, selection.
    static let snappy = Animation.snappy(duration: 0.28)
    /// Default for layout and content changes.
    static let gentle = Animation.smooth(duration: 0.4)
    /// Playful, slightly springy moments: saves, celebrations, mascot reactions.
    static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.7)
    /// Large container morphs such as the capture panel expanding.
    static let hero = Animation.spring(response: 0.5, dampingFraction: 0.86)
    /// Fades and dissolves; also the Reduce Motion substitute for every other curve.
    static let fade = Animation.easeInOut(duration: 0.2)

    static var prefersReducedMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    /// Returns `animation`, or a short dissolve when Reduce Motion is on.
    static func resolved(_ animation: Animation, reduceMotion: Bool = prefersReducedMotion) -> Animation {
        reduceMotion ? fade : animation
    }
}

@discardableResult
func withOffRecordAnimation<Result>(
    _ animation: Animation = OffRecordMotion.gentle,
    _ body: () throws -> Result
) rethrows -> Result {
    try withAnimation(OffRecordMotion.resolved(animation), body)
}

private struct OffRecordAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(OffRecordMotion.resolved(animation, reduceMotion: reduceMotion), value: value)
    }
}

private struct OffRecordShadowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let elevation: OffRecordElevation

    func body(content: Content) -> some View {
        // Dark surfaces separate by tone, so shadows are softened to avoid muddy halos.
        content.shadow(
            color: elevation.color.opacity(colorScheme == .dark ? 0.6 : 1),
            radius: elevation.radius,
            x: 0,
            y: elevation.y
        )
    }
}

enum OffRecordLayout {
    /// Minimum interactive size from the HIG.
    static let minimumTapTarget: CGFloat = 44
    static let pillButtonHeight: CGFloat = 52
    static let readableContentWidth: CGFloat = 720
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
                    .offRecordShadow(shadow ? .card : .none)
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
            .frame(minHeight: OffRecordLayout.pillButtonHeight)
            .padding(.horizontal, OffRecordSpacing.lg)
            .background(fill, in: Capsule())
    }
}

extension View {
    /// Animates changes to `value` with an OffRecord motion token, degrading to a dissolve under Reduce Motion.
    func offRecordAnimation<V: Equatable>(_ animation: Animation = OffRecordMotion.gentle, value: V) -> some View {
        modifier(OffRecordAnimationModifier(animation: animation, value: value))
    }

    func offRecordShadow(_ elevation: OffRecordElevation) -> some View {
        modifier(OffRecordShadowModifier(elevation: elevation))
    }

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

    func offRecordFridayButton() -> some View {
        modifier(OffRecordPillButtonModifier(
            fill: OffRecordColor.brandLavenderDark,
            foreground: OffRecordColor.textOnAccent
        ))
    }

    func offRecordPrivacyButton() -> some View {
        modifier(OffRecordPillButtonModifier(
            fill: OffRecordColor.brandSageDark,
            foreground: OffRecordColor.textOnAccent
        ))
    }

    func offRecordScreenBackground() -> some View {
        background(OffRecordAppBackground().ignoresSafeArea())
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
                .font(compact ? OffRecordTypography.annotation : OffRecordTypography.bodySmall)
                .foregroundStyle(OffRecordColor.brandSageDark)

            if !compact {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(OffRecordTypography.labelSmall)
                        .foregroundStyle(OffRecordColor.textSage)
                    if let subtitle {
                        Text(subtitle)
                            .font(OffRecordTypography.annotation)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var scale: CGFloat {
        switch dynamicTypeSize {
        case ...DynamicTypeSize.large: return 1
        case .xLarge, .xxLarge: return 1.1
        case .xxxLarge: return 1.2
        default: return 1.35
        }
    }

    private var scaledIconSize: CGFloat { iconSize * scale }

    var body: some View {
        ZStack {
            Circle()
                .fill(fill ?? tint.opacity(0.14))
            Image(systemName: systemImage)
                .font(.system(size: scaledIconSize, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size * scale, height: size * scale)
        .accessibilityHidden(true)
    }
}
