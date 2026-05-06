import SwiftUI

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
                            .font(.system(size: isIPad ? 28 : 26, weight: .semibold, design: .rounded))
                            .foregroundColor(OffRecordColor.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(hero.prompt.prompt)
                            .font(.system(size: isIPad ? 22 : 20, weight: .regular, design: .rounded))
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
                        usesStackedLayout: !isIPad,
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
                            .font(.system(size: isIPad ? 28 : 26, weight: .semibold, design: .rounded))
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
                            .font(.system(size: isIPad ? 19 : 18, weight: .semibold, design: .rounded))
                            .foregroundColor(OffRecordColor.textPrimary)
                            .lineLimit(1)

                        Text(hero.prompt.prompt)
                            .font(.system(size: isIPad ? 21 : 19, weight: .regular, design: .rounded))
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
                        usesStackedLayout: !isIPad,
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
    let onAddNote: () -> Void
    let onSkip: () -> Void

    var body: some View {
        DaypartHeroSurface(
            hero: hero,
            height: isIPad ? 184 : 168,
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
                        .font(.system(size: isIPad ? 25 : 24, weight: .semibold, design: .rounded))
                        .foregroundColor(OffRecordColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.92)

                    Text(hero.prompt.prompt)
                        .font(.system(size: isIPad ? 20 : 19, weight: .regular, design: .rounded))
                        .foregroundColor(OffRecordColor.textPrimary.opacity(0.86))
                        .lineSpacing(2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .center, spacing: 16) {
                        Button(action: onAddNote) {
                            Label("Write a note", systemImage: "square.and.pencil")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(OffRecordColor.textBrand)
                        .accessibilityIdentifier("daypartHero.compactCTA")
                    }
                    .frame(minHeight: 44, alignment: .leading)
                }
                .padding(.horizontal, isIPad ? 22 : 18)
                .padding(.bottom, isIPad ? 20 : 18)
            }
        }
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
                .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var meterBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(OffRecordColor.surfaceWarm.opacity(0.62))
        }
    }

    private var meterBorder: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Color.white.opacity(0.52), lineWidth: 1)
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
    let usesStackedLayout: Bool
    let onPrimaryAction: () -> Void
    let onWriteAction: () -> Void
    let onSkip: () -> Void

    var body: some View {
        Group {
            if usesStackedLayout {
                stackedLayout
            } else {
                horizontalLayout
            }
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
    }

    private var primaryButton: some View {
        Button(action: onPrimaryAction) {
            Label(primaryTitle, systemImage: isRecording ? "stop.fill" : "waveform")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .fixedSize(horizontal: true, vertical: false)
                .background {
                    ZStack {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                        Capsule(style: .continuous)
                            .fill(OffRecordColor.surfaceWarm.opacity(0.74))
                    }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.50), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .foregroundColor(OffRecordColor.textBrand)
        .disabled(isProcessing)
        .accessibilityIdentifier("daypartHero.primaryCTA")
    }

    private var writeButton: some View {
        Button(action: onWriteAction) {
            Label("Write", systemImage: "square.and.pencil")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
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

            LinearGradient(
                stops: [
                    .init(color: OffRecordColor.backgroundPrimary.opacity(0.92), location: 0.00),
                    .init(color: OffRecordColor.backgroundPrimary.opacity(0.60), location: 0.48),
                    .init(color: OffRecordColor.backgroundPrimary.opacity(0.10), location: 1.00)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .allowsHitTesting(false)

            content
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: height, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.54), lineWidth: 1)
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
            .font(.system(size: compact ? 13 : 14, weight: .semibold, design: .rounded))
            .foregroundColor(OffRecordColor.textPrimary)
            .padding(.horizontal, compact ? 12 : 14)
            .frame(minHeight: compact ? 30 : 34)
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                    Capsule(style: .continuous)
                        .fill(dayPart.tint.opacity(0.32))
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.50), lineWidth: 1)
            }
    }
}

private struct HeroPrivacyBadge: View {
    var text = "Private"

    var body: some View {
        Label(text, systemImage: "lock.shield.fill")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(OffRecordColor.textSecondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                    Capsule(style: .continuous)
                        .fill(OffRecordColor.surfaceWarm.opacity(0.52))
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.48), lineWidth: 1)
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
