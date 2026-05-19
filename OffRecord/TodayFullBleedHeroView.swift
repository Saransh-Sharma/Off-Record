import SwiftUI

struct TodayFullBleedHeroView: View {
    let hero: SelectedDaypartHero
    let greeting: String
    let dateText: String
    let entriesThisYear: Int
    let todayEntry: DiaryEntry?
    let height: CGFloat
    let topSafeAreaInset: CGFloat
    let isRecording: Bool
    let isProcessing: Bool
    let currentTime: TimeInterval
    let level: Double
    let onPrivacy: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var dateSize: CGFloat = 50
    @ScaledMetric(relativeTo: .title) private var promptTitleSize: CGFloat = 26
    @ScaledMetric(relativeTo: .title3) private var promptQuestionSize: CGFloat = 19

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            readabilityOverlays
            accessibilityMarkers

            VStack(alignment: .leading, spacing: 0) {
                topChrome
                    .padding(.top, topPadding)
                    .padding(.horizontal, OffRecordSpacing.screenX)

                timeChip
                    .padding(.top, 76)
                    .padding(.horizontal, OffRecordSpacing.screenX)

                Spacer(minLength: 18)

                heroContent
                    .padding(.horizontal, OffRecordSpacing.screenX)
                    .padding(.bottom, heroContentBottomPadding)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }

    private var background: some View {
        Group {
            if let imageName = hero.asset?.imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            } else {
                fallbackBackground
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var accessibilityMarkers: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(hero.dayPart.displayName) home")
                .accessibilityIdentifier("homeHero.fullBleed")

            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(hero.dayPart.displayName) illustration")
                .accessibilityIdentifier("daypartHero.imageSurface")
        }
        .frame(width: 1, height: 2)
    }

    private var readabilityOverlays: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: leftReadabilityColor, location: 0.00),
                    .init(color: leftReadabilityColor.opacity(isNight ? 0.24 : 0.52), location: 0.38),
                    .init(color: .clear, location: 0.78)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            if isNight {
                Color.black.opacity(0.16)
            }
        }
        .allowsHitTesting(false)
    }

    private var topChrome: some View {
        HStack(alignment: .center) {
            TodayHeroMetadataChip(
                title: "\(entriesThisYear) this year",
                systemImage: "calendar",
                height: 38
            )
            .accessibilityIdentifier("homeHero.entriesThisYear")

            Spacer(minLength: 12)

            Button(action: onPrivacy) {
                TodayHeroMetadataChip(
                    title: "Privacy",
                    systemImage: "lock.shield.fill",
                    iconOnly: true,
                    height: 40
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Privacy and local AI")
            .accessibilityIdentifier("homeHero.privacy")
        }
    }

    private var timeChip: some View {
        TodayHeroMetadataChip(
            title: hero.dayPart.displayName,
            systemImage: hero.dayPart.symbolName,
            fill: OffRecordColor.surfaceWarm.opacity(isNight ? 0.92 : 0.88),
            foreground: OffRecordColor.textBrand,
            border: OffRecordColor.borderSoft,
            height: 44
        )
        .accessibilityIdentifier("homeHero.timeChip")
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(greeting)
                    .font(OffRecordTypography.bodyLarge)
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(dateText)
                    .font(.system(size: min(dateSize, 58), weight: .heavy, design: .default))
                    .foregroundStyle(primaryText)
                    .lineSpacing(-3)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .frame(maxWidth: 290, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(hero.prompt.title)
                    .font(.system(size: min(promptTitleSize, 30), weight: .bold, design: .default))
                    .foregroundStyle(primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                Text(hero.prompt.prompt)
                    .font(.system(size: min(promptQuestionSize, 23), weight: .medium, design: .default))
                    .foregroundStyle(questionText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let supportingLine = hero.prompt.supportingLine {
                    Text(supportingLine)
                        .font(OffRecordTypography.bodySmall)
                        .foregroundStyle(secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 340, alignment: .leading)

            if isRecording || isProcessing {
                HeroRecordingMeter(
                    currentTime: currentTime,
                    level: level,
                    isProcessing: isProcessing,
                    barCount: 24
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let todayEntry {
                TodayHeroEntryPreviewCard(entry: todayEntry, isNight: isNight)
                    .padding(.top, 2)
            }
        }
    }

    private var fallbackBackground: some View {
        LinearGradient(
            colors: [
                fallbackTint.opacity(0.82),
                OffRecordColor.backgroundPrimary,
                OffRecordColor.backgroundLavenderTint
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
    }

    private var topPadding: CGFloat {
        max(128, topSafeAreaInset + 96)
    }

    private var heroContentBottomPadding: CGFloat {
        todayEntry == nil ? 82 : 214
    }

    private var isNight: Bool {
        hero.dayPart == .night
    }

    private var primaryText: Color {
        isNight ? OffRecordColor.textInverse : OffRecordColor.textBrand
    }

    private var secondaryText: Color {
        isNight ? OffRecordColor.backgroundSecondary : OffRecordColor.textSecondary
    }

    private var questionText: Color {
        isNight ? OffRecordColor.backgroundSecondary : OffRecordColor.textBrand
    }

    private var leftReadabilityColor: Color {
        isNight ? OffRecordColor.darkBackground : OffRecordColor.backgroundPrimary
    }

    private var fallbackTint: Color {
        switch hero.dayPart {
        case .morning:
            return OffRecordColor.backgroundPeachTint
        case .afternoon:
            return OffRecordColor.backgroundSageTint
        case .evening:
            return OffRecordColor.backgroundLavenderTint
        case .night:
            return OffRecordColor.darkSurface
        }
    }
}
