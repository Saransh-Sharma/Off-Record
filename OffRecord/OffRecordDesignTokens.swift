//
//  OffRecordDesignTokens.swift
//  OffRecord
//
//  Pastel design tokens derived from OffRecord Design.md. Colors live in
//  OffRecordSystemShared/OffRecordColor.swift, shared with the widgets.
//

import SwiftUI

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
    var title = String(localized: "Private", comment: "Badge saying the content is kept private")
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
