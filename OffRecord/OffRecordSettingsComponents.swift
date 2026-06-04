import SwiftUI

struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String?
    var footer: String?
    var systemImage: String?
    var tint: Color
    var fill: Color
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        footer: String? = nil,
        systemImage: String? = nil,
        tint: Color,
        fill: Color = OffRecordColor.surfacePrimary,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.footer = footer
        self.systemImage = systemImage
        self.tint = tint
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
            HStack(alignment: .top, spacing: OffRecordSpacing.md) {
                if let systemImage {
                    OffRecordIconBubble(
                        systemImage: systemImage,
                        tint: tint,
                        fill: tint.opacity(0.13),
                        size: 38,
                        iconSize: 15
                    )
                    .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                    Text(title)
                        .font(OffRecordTypography.sectionTitle)
                        .foregroundStyle(OffRecordColor.textHeading)

                    if let subtitle {
                        Text(subtitle)
                            .font(OffRecordTypography.metadata)
                            .foregroundStyle(OffRecordColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
                content
            }

            if let footer {
                Text(footer)
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OffRecordSpacing.xl)
        .offRecordContentCard(cornerRadius: OffRecordRadius.xl, fill: fill)
        .offRecordPointerLift()
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
            VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                Text(title)
                    .font(OffRecordTypography.titleSmall)
                    .foregroundStyle(OffRecordColor.textHeading)

                if let subtitle {
                    Text(subtitle)
                        .font(OffRecordTypography.bodySmall)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, OffRecordSpacing.xs)

            content
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let systemImage: String?
    let title: String
    var subtitle: String?
    var tint: Color = OffRecordColor.textBrand
    @ViewBuilder let trailing: Trailing

    init(
        systemImage: String? = nil,
        title: String,
        subtitle: String? = nil,
        tint: Color = OffRecordColor.textBrand,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalLayout
            verticalLayout
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, OffRecordSpacing.xs)
        .accessibilityElement(children: .contain)
    }

    private var textStack: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
            Text(title)
                .font(OffRecordTypography.bodySmall)
                .foregroundStyle(OffRecordColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var leadingIcon: some View {
        Group {
            if let systemImage {
                OffRecordIconBubble(
                    systemImage: systemImage,
                    tint: tint,
                    fill: tint.opacity(0.13),
                    size: 34,
                    iconSize: 14
                )
                .accessibilityHidden(true)
            }
        }
    }

    private var horizontalLayout: some View {
        HStack(alignment: .center, spacing: OffRecordSpacing.md) {
            leadingIcon
            textStack
            Spacer(minLength: OffRecordSpacing.md)
            trailing
        }
        .frame(minHeight: 44)
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            HStack(alignment: .top, spacing: OffRecordSpacing.md) {
                leadingIcon
                textStack
            }

            trailing
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, systemImage == nil ? 0 : 46)
        }
        .frame(minHeight: 44)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(systemImage: String? = nil, title: String, subtitle: String? = nil, tint: Color = OffRecordColor.textBrand) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.trailing = EmptyView()
    }
}

struct SettingsActionRow: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    var tint: Color = OffRecordColor.textBrand
    var destructive = false

    var body: some View {
        HStack(alignment: .center, spacing: OffRecordSpacing.md) {
            OffRecordIconBubble(
                systemImage: systemImage,
                tint: destructive ? OffRecordColor.textCoral : tint,
                fill: (destructive ? OffRecordColor.textCoral : tint).opacity(0.13),
                size: 38,
                iconSize: 15
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                Text(title)
                    .font(OffRecordTypography.bodySmall)
                    .foregroundStyle(destructive ? OffRecordColor.textCoral : OffRecordColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: OffRecordSpacing.md)

            Image(systemName: "chevron.right")
                .font(OffRecordTypography.metadata)
                .foregroundStyle(OffRecordColor.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsPrimaryButtonStyle: ButtonStyle {
    var fill: Color = OffRecordColor.brandPlum
    var foreground: Color = OffRecordColor.textInverse

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OffRecordTypography.labelMedium)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .padding(.horizontal, OffRecordSpacing.lg)
            .background(fill.opacity(configuration.isPressed ? 0.86 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct SettingsSecondaryButtonStyle: ButtonStyle {
    var tint: Color = OffRecordColor.textBrand
    var fill: Color = OffRecordColor.surfaceWarm

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OffRecordTypography.labelMedium)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 46)
            .padding(.horizontal, OffRecordSpacing.lg)
            .background(fill.opacity(configuration.isPressed ? 0.78 : 1), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.18), lineWidth: 1))
    }
}

struct ThemeButton: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: OffRecordSpacing.sm) {
                ZStack {
                    Color.clear
                        .frame(width: 48, height: 48)
                        .offRecordGlassControl(
                            tint: isSelected ? theme.accentColor : nil,
                            in: Circle(),
                            fallbackFill: theme.accentColor.opacity(0.2)
                        )

                    Circle()
                        .fill(theme.accentColor.opacity(isSelected ? 1 : 0.8))
                        .frame(width: 32, height: 32)

                    Image(systemName: theme.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.swatchForegroundColor)
                }
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(theme.accentColor, lineWidth: 2)
                            .frame(width: 52, height: 52)
                    }
                }

                Text(theme.rawValue)
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(isSelected ? theme.readableAccentColor : OffRecordColor.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 76)
        }
        .buttonStyle(.plain)
        .offRecordPointerLift()
        .accessibilityLabel(theme.rawValue)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct StorageRow: View {
    let label: String
    let bytes: Int64
    let totalBytes: Int64
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            SettingsRow(systemImage: icon, title: label, tint: color) {
                Text(formattedSize)
                    .font(OffRecordTypography.bodySmall)
                    .foregroundStyle(OffRecordColor.textPrimary)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(color.opacity(0.13))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color.opacity(0.72))
                            .frame(width: progress > 0 ? max(6, proxy.size.width * progress) : 0)
                    }
            }
            .frame(height: 7)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(formattedSize)")
    }

    private var progress: CGFloat {
        guard totalBytes > 0 else { return 0 }
        return min(1, CGFloat(bytes) / CGFloat(totalBytes))
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct PrivacyInfoRow: View {
    let icon: String
    let title: String
    let description: String
    var tint: Color = OffRecordColor.textSage

    var body: some View {
        SettingsRow(
            systemImage: icon,
            title: title,
            subtitle: description,
            tint: tint
        )
    }
}
