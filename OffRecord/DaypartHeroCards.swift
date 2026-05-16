import SwiftUI

private enum DaypartHeroStyling {
    static let surfaceStroke = OffRecordColor.borderWarm.opacity(0.72)
    static let chromeStroke = Color.white.opacity(0.24)
    static let chromeWarmStroke = OffRecordColor.borderWarm.opacity(0.82)
    static let chromeSageStroke = OffRecordColor.borderSage.opacity(0.86)

    static func chromeGradient(tint: Color, warmth: Color = OffRecordColor.surfaceWarm) -> LinearGradient {
        LinearGradient(
            colors: [
                warmth.opacity(0.94),
                tint.opacity(0.78)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let atmosphereOverlay = LinearGradient(
        stops: [
            .init(color: OffRecordColor.brandPlum.opacity(0.08), location: 0.00),
            .init(color: OffRecordColor.brandSageDark.opacity(0.05), location: 0.42),
            .init(color: OffRecordColor.brandPeach.opacity(0.08), location: 1.00)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let readabilityOverlay = LinearGradient(
        stops: [
            .init(color: OffRecordColor.surfaceWarm.opacity(0.84), location: 0.00),
            .init(color: OffRecordColor.backgroundBlushTint.opacity(0.72), location: 0.26),
            .init(color: OffRecordColor.backgroundLavenderTint.opacity(0.36), location: 0.56),
            .init(color: OffRecordColor.surfaceWarm.opacity(0.08), location: 0.82),
            .init(color: .clear, location: 1.00)
        ],
        startPoint: .bottom,
        endPoint: .top
    )

    static let vignetteOverlay = RadialGradient(
        colors: [
            OffRecordColor.brandPeach.opacity(0.12),
            Color.clear
        ],
        center: .bottomLeading,
        startRadius: 16,
        endRadius: 280
    )
}

struct LargeDaypartHeroCard: View {
    let hero: SelectedDaypartHero
    let isIPad: Bool
    let isRecording: Bool
    let isProcessing: Bool
    let currentTime: TimeInterval
    let level: Double
    let onPrimary: () -> Void
    let onWrite: () -> Void
    let onSkip: () -> Void
    let onStop: () -> Void

    private var cardHeight: CGFloat {
        if isRecording || isProcessing {
            return isIPad ? 424 : 408
        }
        return isIPad ? 368 : 348
    }

    var body: some View {
        DaypartHeroSurface(
            hero: hero,
            height: cardHeight,
            cornerRadius: isIPad ? 32 : 30,
            accessibilityIdentifier: "daypartHero.large"
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    DaypartHeroPill(dayPart: hero.dayPart)
                    Spacer(minLength: 12)
                    HeroPrivacyBadge()
                }
                .padding(.horizontal, isIPad ? 24 : 20)
                .padding(.top, isIPad ? 22 : 18)

                Spacer(minLength: isRecording || isProcessing ? 18 : 48)

                VStack(alignment: .leading, spacing: isIPad ? 14 : 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(hero.prompt.title)
                            .font(OffRecordTypography.titleLarge)
                            .foregroundColor(OffRecordColor.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(hero.prompt.prompt)
                            .font(OffRecordTypography.titleSmall)
                            .foregroundColor(OffRecordColor.textPrimary.opacity(0.86))
                            .lineSpacing(3)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(hero.prompt.supportingLine ?? "")
                            .font(OffRecordTypography.bodySmall)
                            .foregroundColor(OffRecordColor.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isRecording || isProcessing {
                        HeroRecordingMeter(
                            currentTime: currentTime,
                            level: level,
                            isProcessing: isProcessing,
                            barCount: isIPad ? 34 : 28
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    DaypartHeroActionRow(
                        isRecording: isRecording,
                        isProcessing: isProcessing,
                        onPrimaryAction: isRecording ? onStop : onPrimary,
                        onWriteAction: onWrite,
                        onSkip: onSkip
                    )
                }
                .padding(.horizontal, isIPad ? 24 : 20)
                .padding(.bottom, isIPad ? 24 : 20)
            }
        }
    }
}

struct WelcomeDaypartHeroCard: View {
    let hero: SelectedDaypartHero
    let authorName: String
    let isIPad: Bool
    let isRecording: Bool
    let isProcessing: Bool
    let currentTime: TimeInterval
    let level: Double
    let onPrimary: () -> Void
    let onWrite: () -> Void
    let onSkip: () -> Void
    let onStop: () -> Void

    private var cardHeight: CGFloat {
        if isRecording || isProcessing {
            return isIPad ? 452 : 432
        }
        return isIPad ? 368 : 348
    }

    var body: some View {
        DaypartHeroSurface(
            hero: hero,
            height: cardHeight,
            cornerRadius: isIPad ? 32 : 30,
            accessibilityIdentifier: "daypartHero.welcome"
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    DaypartHeroPill(dayPart: hero.dayPart)
                    Spacer(minLength: 12)
                    HeroPrivacyBadge(text: "Private by design")
                }
                .padding(.horizontal, isIPad ? 24 : 20)
                .padding(.top, isIPad ? 22 : 18)

                Spacer(minLength: isRecording || isProcessing ? 16 : 36)

                VStack(alignment: .leading, spacing: isIPad ? 13 : 11) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Welcome to your private diary")
                            .font(OffRecordTypography.titleLarge)
                            .foregroundColor(OffRecordColor.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Start with one thought. OffRecord keeps it personal, searchable, and yours.")
                            .font(OffRecordTypography.bodyMedium)
                            .foregroundColor(OffRecordColor.textPrimary.opacity(0.78))
                            .lineSpacing(2)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(hero.prompt.title)
                            .font(OffRecordTypography.labelLarge)
                            .foregroundColor(OffRecordColor.textPrimary)
                            .lineLimit(1)

                        Text(hero.prompt.prompt)
                            .font(OffRecordTypography.titleSmall)
                            .foregroundColor(OffRecordColor.textPrimary.opacity(0.86))
                            .lineSpacing(3)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isRecording || isProcessing {
                        HeroRecordingMeter(
                            currentTime: currentTime,
                            level: level,
                            isProcessing: isProcessing,
                            barCount: isIPad ? 34 : 28
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    DaypartHeroActionRow(
                        isRecording: isRecording,
                        isProcessing: isProcessing,
                        onPrimaryAction: isRecording ? onStop : onPrimary,
                        onWriteAction: onWrite,
                        onSkip: onSkip
                    )
                }
                .padding(.horizontal, isIPad ? 24 : 20)
                .padding(.bottom, isIPad ? 24 : 20)
            }
        }
    }
}

struct CompactDaypartHeroCard: View {
    let hero: SelectedDaypartHero
    let isIPad: Bool
    let onRecord: () -> Void
    let onAddNote: () -> Void
    let onSkip: () -> Void

    var body: some View {
        DaypartHeroSurface(
            hero: hero,
            height: isIPad ? 204 : 196,
            cornerRadius: isIPad ? 28 : 24,
            accessibilityIdentifier: "daypartHero.compact"
        ) {
            VStack(alignment: .leading, spacing: 0) {
                DaypartHeroPill(dayPart: hero.dayPart, compact: true)
                    .padding(.horizontal, isIPad ? 22 : 18)
                    .padding(.top, isIPad ? 18 : 16)

                Spacer(minLength: 18)

                VStack(alignment: .leading, spacing: 8) {
                    Text(hero.prompt.title)
                        .font(OffRecordTypography.titleMedium)
                        .foregroundColor(OffRecordColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.92)

                    Text(hero.prompt.prompt)
                        .font(OffRecordTypography.bodyLarge)
                        .foregroundColor(OffRecordColor.textPrimary.opacity(0.86))
                        .lineSpacing(2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    CompactDaypartHeroActionRow(
                        onRecordAction: onRecord,
                        onWriteAction: onAddNote
                    )
                }
                .padding(.horizontal, isIPad ? 22 : 18)
                .padding(.bottom, isIPad ? 20 : 18)
            }
        }
    }
}

private struct CompactDaypartHeroActionRow: View {
    let onRecordAction: () -> Void
    let onWriteAction: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalLayout
            stackedLayout
        }
        .frame(minHeight: 44, alignment: .leading)
    }

    private var horizontalLayout: some View {
        HStack(alignment: .center, spacing: 14) {
            recordButton
            writeButton
        }
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            recordButton
            writeButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordButton: some View {
        Button(action: onRecordAction) {
            Label("Start recording", systemImage: "waveform")
                .font(OffRecordTypography.labelLarge)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .fixedSize(horizontal: true, vertical: false)
                .background {
                    Capsule(style: .continuous)
                        .fill(DaypartHeroStyling.chromeGradient(tint: OffRecordColor.backgroundLavenderTint))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(DaypartHeroStyling.chromeWarmStroke, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .foregroundColor(OffRecordColor.textBrand)
        .accessibilityIdentifier("daypartHero.compactRecordCTA")
    }

    private var writeButton: some View {
        Button(action: onWriteAction) {
            Label("Write", systemImage: "square.and.pencil")
                .font(OffRecordTypography.labelLarge)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .foregroundColor(OffRecordColor.textPrimary.opacity(0.76))
        .accessibilityIdentifier("daypartHero.compactCTA")
    }
}

struct HeroRecordingMeter: View {
    let currentTime: TimeInterval
    let level: Double
    let isProcessing: Bool
    var barCount = 28

    var body: some View {
        meterContent
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(meterBackground)
            .overlay(meterBorder)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isProcessing ? "Saving reflection" : "Recording \(formattedTime)")
            .accessibilityIdentifier("daypartHero.recordingMeter")
    }

    private var meterContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            meterHeader
            levelBars
        }
    }

    private var meterHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(isProcessing ? "Saving reflection..." : formattedTime)
                .font(OffRecordTypography.numberMedium)
                .foregroundColor(OffRecordColor.textPrimary)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Circle()
                    .fill(isProcessing ? OffRecordColor.textSecondary : OffRecordColor.brandCoral)
                    .frame(width: 8, height: 8)

                Text(isProcessing ? "Processing" : "Recording")
                    .font(OffRecordTypography.labelMedium)
                    .foregroundColor(OffRecordColor.textSecondary)
            }
        }
    }

    private var levelBars: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                levelBar(at: index)
            }
        }
        .frame(height: 34)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var meterBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                DaypartHeroStyling.chromeGradient(
                    tint: isProcessing ? OffRecordColor.backgroundPeachTint : OffRecordColor.backgroundLavenderTint
                )
            )
    }

    private var meterBorder: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(DaypartHeroStyling.chromeWarmStroke, lineWidth: 1)
    }

    private func levelBar(at index: Int) -> some View {
        let height = barHeight(at: index)
        return Capsule()
            .fill(OffRecordColor.textBrand.opacity(0.28 + Double(height) * 0.46))
            .frame(width: 4, height: max(6, 7 + height * 26))
    }

    private var formattedTime: String {
        let totalSeconds = Int(currentTime)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func barHeight(at index: Int) -> CGFloat {
        let clampedLevel = CGFloat(max(0, min(1, level)))
        let wave = CGFloat((sin(Double(index) * 0.72) + 1) / 2)
        return max(0.18, min(1, clampedLevel * 0.78 + wave * 0.22))
    }
}

private struct DaypartHeroActionRow: View {
    let isRecording: Bool
    let isProcessing: Bool
    let onPrimaryAction: () -> Void
    let onWriteAction: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalLayout
            stackedLayout
        }
        .frame(minHeight: 44, alignment: .leading)
    }

    private var horizontalLayout: some View {
        HStack(alignment: .center, spacing: 18) {
            primaryButton
            writeButton
        }
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                primaryButton
                writeButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryButton: some View {
        Button(action: onPrimaryAction) {
            Label(primaryTitle, systemImage: primarySymbolName)
                .font(OffRecordTypography.labelLarge)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .fixedSize(horizontal: true, vertical: false)
                .background {
                    Capsule(style: .continuous)
                        .fill(DaypartHeroStyling.chromeGradient(tint: primaryButtonTint))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(primaryButtonStroke, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .foregroundColor(primaryForegroundColor)
        .disabled(isProcessing)
        .accessibilityIdentifier("daypartHero.primaryCTA")
    }

    private var writeButton: some View {
        Button(action: onWriteAction) {
            Label("Write", systemImage: "square.and.pencil")
                .font(OffRecordTypography.labelLarge)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .foregroundColor(OffRecordColor.textPrimary.opacity(0.76))
        .disabled(isRecording || isProcessing)
        .accessibilityIdentifier("daypartHero.writeCTA")
    }

    private var primaryTitle: String {
        if isProcessing {
            return "Saving"
        }
        return isRecording ? "Stop recording" : "Start recording"
    }

    private var primarySymbolName: String {
        if isRecording {
            return "stop.fill"
        }
        return "waveform"
    }

    private var primaryButtonTint: Color {
        if isRecording {
            return OffRecordColor.backgroundBlushTint
        }
        if isProcessing {
            return OffRecordColor.backgroundPeachTint
        }
        return OffRecordColor.backgroundLavenderTint
    }

    private var primaryForegroundColor: Color {
        isRecording ? OffRecordColor.textCoral : OffRecordColor.textBrand
    }

    private var primaryButtonStroke: Color {
        isRecording ? OffRecordColor.brandCoral.opacity(0.55) : DaypartHeroStyling.chromeWarmStroke
    }
}

private struct DaypartHeroSurface<Content: View>: View {
    let hero: SelectedDaypartHero
    let height: CGFloat
    let cornerRadius: CGFloat
    let accessibilityIdentifier: String
    let content: Content

    init(
        hero: SelectedDaypartHero,
        height: CGFloat,
        cornerRadius: CGFloat,
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) {
        self.hero = hero
        self.height = height
        self.cornerRadius = cornerRadius
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            DaypartHeroBackground(asset: hero.asset, dayPart: hero.dayPart)

            DaypartHeroStyling.atmosphereOverlay
                .blendMode(.multiply)
                .allowsHitTesting(false)

            ZStack {
                DaypartHeroStyling.readabilityOverlay
                DaypartHeroStyling.vignetteOverlay
            }
            .allowsHitTesting(false)

            content
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: height, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(DaypartHeroStyling.surfaceStroke, lineWidth: 1)
        }
        .shadow(color: OffRecordShadow.cardColor.opacity(0.72), radius: 30, x: 0, y: 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(hero.dayPart.displayName) reflection prompt")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct DaypartHeroBackground: View {
    let asset: DaypartHeroAsset?
    let dayPart: DayPart

    var body: some View {
        Group {
            if let imageName = asset?.imageName, UIImage(named: imageName) != nil {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel("\(dayPart.displayName) illustration")
            } else {
                fallbackGradient
                    .accessibilityLabel("\(dayPart.displayName) atmospheric illustration")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityIdentifier("daypartHero.imageSurface")
    }

    private var fallbackGradient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    dayPart.tint.opacity(0.76),
                    OffRecordColor.backgroundPrimary,
                    OffRecordColor.backgroundLavenderTint.opacity(0.84)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.70),
                    Color.white.opacity(0.08)
                ],
                center: .topTrailing,
                startRadius: 12,
                endRadius: 220
            )
        }
    }
}

private struct DaypartHeroPill: View {
    let dayPart: DayPart
    var compact = false

    var body: some View {
        Label(dayPart.displayName, systemImage: dayPart.symbolName)
            .font(OffRecordTypography.badgeLabel)
            .foregroundColor(OffRecordColor.textPrimary)
            .padding(.horizontal, compact ? 12 : 14)
            .frame(minHeight: compact ? 30 : 34)
            .background {
                Capsule(style: .continuous)
                    .fill(DaypartHeroStyling.chromeGradient(tint: dayPart.tint))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(DaypartHeroStyling.chromeStroke, lineWidth: 1)
            }
    }
}

private struct HeroPrivacyBadge: View {
    var text = "Private"

    var body: some View {
        Label(text, systemImage: "lock.shield.fill")
            .font(OffRecordTypography.labelSmall)
            .foregroundColor(OffRecordColor.textSecondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background {
                Capsule(style: .continuous)
                    .fill(DaypartHeroStyling.chromeGradient(tint: OffRecordColor.backgroundSageTint))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(DaypartHeroStyling.chromeSageStroke, lineWidth: 1)
            }
    }
}

private extension DayPart {
    var tint: Color {
        switch self {
        case .morning:
            return OffRecordColor.backgroundPeachTint
        case .afternoon:
            return OffRecordColor.backgroundSageTint
        case .evening:
            return OffRecordColor.backgroundLavenderTint
        case .night:
            return OffRecordColor.surfacePeach.opacity(0.86)
        }
    }
}
