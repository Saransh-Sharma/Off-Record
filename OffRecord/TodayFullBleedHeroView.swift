import SwiftUI

/// Daypart illustration hero: greeting, date, one prompt, and one action.
/// Height follows its content (and Dynamic Type) instead of a screen fraction.
struct TodayFullBleedHeroView: View {
    let hero: SelectedDaypartHero
    let greeting: String
    let date: Date
    let entriesThisYear: Int
    let todayEntry: DiaryEntry?
    let topSafeAreaInset: CGFloat
    let horizontalPadding: CGFloat
    let onSpeak: () -> Void
    let onWrite: () -> Void
    let onAnotherPrompt: () -> Void
    let onPrivacy: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let artReveal: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topChrome
                .padding(.top, topSafeAreaInset + OffRecordSpacing.md)

            // Leaves room for the illustration to breathe above the text.
            Spacer(minLength: Self.artReveal)

            heroContent
                .padding(.bottom, OffRecordSpacing.xxl)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 460 + topSafeAreaInset, alignment: .bottom)
        .background { stretchyBackground }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: OffRecordRadius.xxl, bottomTrailingRadius: OffRecordRadius.xxl, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(hero.dayPart.displayName) home")
        .accessibilityIdentifier("homeHero.fullBleed")
    }

    // MARK: Background

    /// The art stretches when pulled down instead of revealing a gap.
    private var stretchyBackground: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .scrollView).minY
            let stretch = reduceMotion ? 0 : max(0, minY)
            ZStack {
                artwork
                readabilityOverlay
            }
            .frame(width: proxy.size.width, height: proxy.size.height + stretch)
            .offset(y: -stretch)
        }
    }

    private var artwork: some View {
        Group {
            if let imageName = hero.asset?.imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [fallbackTint.opacity(0.82), OffRecordColor.backgroundPrimary, OffRecordColor.backgroundLavenderTint],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var readabilityOverlay: some View {
        ZStack {
            // A soft wash rising from the bottom keeps text readable over any illustration.
            LinearGradient(stops: washStops, startPoint: .top, endPoint: .bottom)
            if colorScheme == .dark && !isNight {
                Color.black.opacity(0.18)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Chrome

    private var topChrome: some View {
        // Same buttons at every size; very large text stacks them instead of clipping.
        let layout = dynamicTypeSize >= .xxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: OffRecordSpacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: OffRecordSpacing.sm))
        return layout {
            TodayHeroMetadataChip(
                title: "\(entriesThisYear) this year",
                systemImage: "calendar"
            )
            .accessibilityIdentifier("homeHero.entriesThisYear")

            TodayHeroMetadataChip(
                title: hero.dayPart.displayName,
                systemImage: hero.dayPart.symbolName,
                fill: OffRecordColor.surfaceWarm,
                foreground: OffRecordColor.textBrand,
                border: OffRecordColor.borderSoft
            )
            .accessibilityIdentifier("homeHero.timeChip")

            Spacer(minLength: OffRecordSpacing.sm)

            Button(action: onPrivacy) {
                TodayHeroMetadataChip(
                    title: "Privacy",
                    systemImage: "lock.shield.fill",
                    iconOnly: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Privacy and local AI")
            .accessibilityIdentifier("homeHero.privacy")
        }
    }

    // MARK: Content

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
            VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                Text(greeting)
                    .font(OffRecordTypography.bodyLarge)
                    // Primary color: it sits over the illustration, where secondary text is too faint.
                    .foregroundStyle(primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(.largeTitle, design: .default, weight: .heavy))
                    .foregroundStyle(primaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("homeHero.dateTitle")
            }

            VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                Text(hero.prompt.title)
                    .font(OffRecordTypography.titleSmall)
                    .foregroundStyle(primaryText)
                Text(hero.prompt.prompt)
                    .font(OffRecordTypography.bodyLarge)
                    .foregroundStyle(questionText)
                    .fixedSize(horizontal: false, vertical: true)
                if let supportingLine = hero.prompt.supportingLine {
                    Text(supportingLine)
                        .font(OffRecordTypography.bodySmall)
                        .foregroundStyle(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 420, alignment: .leading)
            .id(hero.prompt.id)
            .transition(.opacity.combined(with: .move(edge: .leading)))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("homeHero.prompt")

            actionRow

            if let todayEntry {
                TodayHeroEntryPreviewCard(entry: todayEntry, isNight: isDarkPresentation)
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private var actionRow: some View {
        // AnyLayout keeps the same buttons as the arrangement changes, so each one grows with
        // Dynamic Type instead of being swapped out; large sizes stack them one per row.
        let layout = dynamicTypeSize >= .xxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: OffRecordSpacing.sm))
            : AnyLayout(HStackLayout(spacing: OffRecordSpacing.sm))
        return layout {
            speakButton
            writeButton
            anotherPromptButton
        }
    }

    private var speakButton: some View {
        Button(action: onSpeak) {
            Label(todayEntry == nil ? "Speak" : "Add a thought", systemImage: "mic.fill")
                .offRecordPillButton()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Starts a private voice recording for this prompt.")
        .accessibilityIdentifier("homeHero.speak")
    }

    private var writeButton: some View {
        Button(action: onWrite) {
            Label("Write", systemImage: "square.and.pencil")
        }
        .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textBrand, fill: OffRecordColor.surfacePrimary.opacity(0.88)))
        .accessibilityIdentifier("homeHero.write")
    }

    private var anotherPromptButton: some View {
        Button(action: onAnotherPrompt) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(OffRecordTypography.labelLarge)
                .foregroundStyle(OffRecordColor.textBrand)
                .frame(width: 48, height: 48)
                .background(OffRecordColor.surfacePrimary.opacity(0.88), in: Circle())
                .overlay(Circle().stroke(OffRecordColor.borderSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show another prompt")
        .accessibilityIdentifier("homeHero.anotherPrompt")
    }

    // MARK: Colors

    private var isNight: Bool {
        hero.dayPart == .night
    }

    /// Night art is dark; in dark mode every daypart is dimmed. Both use light text.
    private var isDarkPresentation: Bool {
        isNight || colorScheme == .dark
    }

    /// Dark mode puts light text over the bright daytime art, so the wash starts higher there.
    private var washStops: [Gradient.Stop] {
        if colorScheme == .dark && !isNight {
            return [
                .init(color: .clear, location: 0.0),
                .init(color: washColor.opacity(0.45), location: 0.3),
                .init(color: washColor.opacity(0.78), location: 0.5),
                .init(color: washColor.opacity(0.9), location: 0.75),
                .init(color: washColor.opacity(0.95), location: 1.0)
            ]
        }
        return [
            .init(color: .clear, location: 0.0),
            .init(color: washColor.opacity(0.18), location: 0.35),
            .init(color: washColor.opacity(isDarkPresentation ? 0.78 : 0.72), location: 0.72),
            .init(color: washColor.opacity(isDarkPresentation ? 0.92 : 0.9), location: 1.0)
        ]
    }

    private var washColor: Color {
        isNight ? Color(hex: 0x18131D) : OffRecordColor.backgroundPrimary
    }

    private var primaryText: Color {
        isNight ? OffRecordColor.textInverse : OffRecordColor.textBrand
    }

    private var secondaryText: Color {
        isNight ? Color(hex: 0xE6DDE8) : OffRecordColor.textSecondary
    }

    private var questionText: Color {
        isNight ? Color(hex: 0xF3ECF5) : OffRecordColor.textBrand
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
