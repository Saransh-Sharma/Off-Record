//
//  FridayProfileCard.swift
//  OffRecord
//
//  Shareable personality profile card — "Spotify Wrapped for your personality."
//  Pulls data from FridayAssistantEngine to create a visually striking,
//  share-worthy summary of who you are based on your journal entries.
//

import SwiftUI

// MARK: - Friday Profile Data

struct FridayProfile {
    let traits: [Trait]
    let signatureWords: [String]
    let peakTime: String
    let totalEntries: Int
    let totalWords: Int
    let dominantMood: String
    let emotionalRange: String
    let communicationStyle: String
    let thinkingStyle: String
    let topPerson: String?
    let topTopic: String?
    let maturityLevel: String

    struct Trait {
        let label: String
        let value: Double       // 0-1
        let lowLabel: String
        let highLabel: String
        let displayLabel: String // which end the user leans toward
    }
}

// MARK: - Profile Generator

@MainActor
struct FridayProfileGenerator {

    static func generate() -> FridayProfile {
        let assistant = FridayAssistantEngine.shared

        // Traits
        var traits: [FridayProfile.Trait] = []

        let expr = assistant.communicationStyle.expressiveness
        traits.append(.init(
            label: String(localized: "Expression", comment: "Personality card trait"),
            value: expr,
            lowLabel: String(localized: "Reserved", comment: "Low end of the “Expression” scale"),
            highLabel: String(localized: "Expressive", comment: "High end of the “Expression” scale"),
            displayLabel: expr > 0.6 ? String(localized: "Expressive", comment: "Where the user leans on the “Expression” scale")
                : expr < 0.4 ? String(localized: "Reserved", comment: "Where the user leans on the “Expression” scale")
                : String(localized: "Balanced", comment: "Where the user leans on the “Expression” scale")
        ))

        let direct = assistant.communicationStyle.directness
        traits.append(.init(
            label: String(localized: "Directness", comment: "Personality card trait"),
            value: direct,
            lowLabel: String(localized: "Nuanced", comment: "Low end of the “Directness” scale"),
            highLabel: String(localized: "Direct", comment: "High end of the “Directness” scale"),
            displayLabel: direct > 0.6 ? String(localized: "Direct", comment: "Where the user leans on the “Directness” scale")
                : direct < 0.4 ? String(localized: "Nuanced", comment: "Where the user leans on the “Directness” scale")
                : String(localized: "Measured", comment: "Where the user leans on the “Directness” scale")
        ))

        let analytical = assistant.thoughtPatterns.analyticalScore
        traits.append(.init(
            label: String(localized: "Thinking", comment: "Personality card trait"),
            value: analytical,
            lowLabel: String(localized: "Intuitive", comment: "Low end of the “Thinking” scale"),
            highLabel: String(localized: "Analytical", comment: "High end of the “Thinking” scale"),
            displayLabel: analytical > 0.6 ? String(localized: "Analytical", comment: "Where the user leans on the “Thinking” scale")
                : analytical < 0.4 ? String(localized: "Intuitive", comment: "Where the user leans on the “Thinking” scale")
                : String(localized: "Balanced", comment: "Where the user leans on the “Thinking” scale")
        ))

        let timeFocus = assistant.thoughtPatterns.futureOriented
        traits.append(.init(
            label: String(localized: "Time Focus", comment: "Personality card trait"),
            value: timeFocus,
            lowLabel: String(localized: "Past", comment: "Low end of the “Time Focus” scale"),
            highLabel: String(localized: "Future", comment: "High end of the “Time Focus” scale"),
            displayLabel: timeFocus > 0.6 ? String(localized: "Future-focused", comment: "Where the user leans on the “Time Focus” scale")
                : timeFocus < 0.4 ? String(localized: "Reflective", comment: "Where the user leans on the “Time Focus” scale")
                : String(localized: "Present-focused", comment: "Where the user leans on the “Time Focus” scale")
        ))

        let growth = assistant.thoughtPatterns.growthMindsetScore
        traits.append(.init(
            label: String(localized: "Mindset", comment: "Personality card trait"),
            value: growth,
            lowLabel: String(localized: "Fixed", comment: "Low end of the “Mindset” scale"),
            highLabel: String(localized: "Growth", comment: "High end of the “Mindset” scale"),
            displayLabel: growth > 0.6 ? String(localized: "Growth-minded", comment: "Where the user leans on the “Mindset” scale")
                : growth < 0.4 ? String(localized: "Steady", comment: "Where the user leans on the “Mindset” scale")
                : String(localized: "Evolving", comment: "Where the user leans on the “Mindset” scale")
        ))

        // Signature words
        let topWords = assistant.communicationStyle.signatureWords
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }

        // Peak time
        let peakHour = assistant.behavioralPatterns.peakHour ?? 21
        let peakTime = formatHour(peakHour)

        // Dominant mood
        let dominantMood: String
        if let topMood = assistant.emotionalSignature.emotionFrequency
            .max(by: { $0.value < $1.value })?.key {
            dominantMood = Mood(rawValue: topMood)?.displayName ?? topMood.capitalized
        } else {
            dominantMood = String(localized: "Neutral", comment: "Top mood when there isn’t enough mood data")
        }

        // Emotional range
        let range = assistant.emotionalSignature.emotionalRange
        let emotionalRange = range > 0.6 ? String(localized: "Wide", comment: "How much the user’s mood varies")
            : range < 0.3 ? String(localized: "Steady", comment: "How much the user’s mood varies")
            : String(localized: "Moderate", comment: "How much the user’s mood varies")

        // Communication style summary
        let formality = assistant.communicationStyle.formalityLevel
        let communicationStyle: String
        if formality > 0.6 && direct > 0.6 {
            communicationStyle = String(localized: "Clear & Professional")
        } else if formality < 0.4 && expr > 0.6 {
            communicationStyle = String(localized: "Casual & Expressive")
        } else if direct > 0.6 && expr < 0.4 {
            communicationStyle = String(localized: "Direct & Reserved")
        } else if formality < 0.4 && direct < 0.4 {
            communicationStyle = String(localized: "Soft-Spoken", comment: "Writing style label")
        } else {
            communicationStyle = String(localized: "Adaptive", comment: "Writing style label")
        }

        // Thinking style summary
        let abstract = assistant.thoughtPatterns.abstractScore
        let thinkingStyle: String
        if analytical > 0.6 && abstract > 0.6 {
            thinkingStyle = String(localized: "Conceptual Thinker")
        } else if analytical > 0.6 && abstract < 0.4 {
            thinkingStyle = String(localized: "Practical Analyst")
        } else if analytical < 0.4 && abstract > 0.6 {
            thinkingStyle = String(localized: "Creative Dreamer")
        } else if analytical < 0.4 && abstract < 0.4 {
            thinkingStyle = String(localized: "Grounded Feeler")
        } else {
            thinkingStyle = String(localized: "Flexible Thinker")
        }

        // Top person & topic from knowledge graph
        let topPerson = assistant.knowledgeGraph.fridayVisibleNodes(ofType: .person, limit: 1).first?.label
        let topTopic = assistant.knowledgeGraph.fridayVisibleNodes(ofType: .topic, limit: 1).first?.label

        return FridayProfile(
            traits: traits,
            signatureWords: topWords,
            peakTime: peakTime,
            totalEntries: assistant.behavioralPatterns.totalEntries,
            totalWords: assistant.behavioralPatterns.totalWords,
            dominantMood: dominantMood,
            emotionalRange: emotionalRange,
            communicationStyle: communicationStyle,
            thinkingStyle: thinkingStyle,
            topPerson: topPerson,
            topTopic: topTopic,
            maturityLevel: assistant.summary.maturityLevel.displayName
        )
    }

    /// The hour in the user's locale, like "9 PM".
    private static func formatHour(_ hour: Int) -> String {
        // A fixed day with no daylight-saving change, so every hour exists.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let date = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour)) else {
            return String(hour)
        }
        return date.formatted(.dateTime.hour())
    }
}

// MARK: - Profile Card View (in-app)

/// The single place to view and share the personality card. It appears once
/// Friday has enough entries for the traits to mean something.
struct FridayProfileCardSection: View {
    static let minimumEntries = 10

    @State private var profile: FridayProfile?
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var shareTrigger = 0

    var body: some View {
        Group {
            if let profile {
                if profile.totalEntries >= Self.minimumEntries {
                    unlockedCard(profile)
                } else if profile.totalEntries > 0 {
                    lockedHint(entries: profile.totalEntries)
                }
            }
        }
        .onAppear { profile = FridayProfileGenerator.generate() }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(activityItems: [
                    image,
                    PersonalityCardRenderer.shareText
                ])
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: shareTrigger)
    }

    private func unlockedCard(_ profile: FridayProfile) -> some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            HStack(spacing: OffRecordSpacing.sm) {
                FridayMascotView(pose: .idle, size: 34)
                    .accessibilityHidden(true)
                Text("Personality Card")
                    .font(OffRecordTypography.sectionTitle)
                    .foregroundStyle(OffRecordColor.textHeading)
                Spacer(minLength: OffRecordSpacing.sm)
                Menu {
                    Button {
                        shareProfile(profile, format: .story)
                    } label: {
                        Label("Tall (Stories)", systemImage: "rectangle.portrait")
                    }
                    Button {
                        shareProfile(profile, format: .landscape)
                    } label: {
                        Label("Wide (Posts)", systemImage: "rectangle")
                    }
                } label: {
                    Label(String(localized: "Share", comment: "Button that shares the personality card"), systemImage: "square.and.arrow.up")
                        .font(OffRecordTypography.labelSmall)
                        .foregroundStyle(OffRecordColor.textAqua)
                        .frame(minWidth: OffRecordLayout.minimumTapTarget, minHeight: OffRecordLayout.minimumTapTarget)
                }
                .accessibilityLabel("Share Personality Card")
                .accessibilityHint("Shares the card as a tall or wide image.")
                .accessibilityIdentifier("friday.shareProfileCard")
            }

            FridayProfileCardContent(profile: profile)
        }
    }

    private func lockedHint(entries: Int) -> some View {
        HStack(spacing: OffRecordSpacing.md) {
            OffRecordIconBubble(
                systemImage: "person.text.rectangle",
                tint: OffRecordColor.textLavender,
                fill: OffRecordColor.backgroundLavenderTint,
                size: 36,
                iconSize: 15
            )
            VStack(alignment: .leading, spacing: OffRecordSpacing.xxs) {
                Text("Personality Card")
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textHeading)
                Text("I’ll make this after \(Self.minimumEntries) entries. You have \(entries).")
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(OffRecordSpacing.lg)
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceLavender)
        .accessibilityElement(children: .combine)
    }

    private func shareProfile(_ profile: FridayProfile, format: PersonalityCardFormat) {
        Task { @MainActor in
            if let image = PersonalityCardRenderer.renderCard(profile: profile, format: format) {
                shareImage = image
                shareTrigger += 1
                showShareSheet = true
            }
        }
    }
}

// MARK: - Card Content (shown in-app)

struct FridayProfileCardContent: View {
    let profile: FridayProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Style labels
            HStack(spacing: 12) {
                styleBadge(profile.communicationStyle, color: OffRecordColor.brandAqua)
                styleBadge(profile.thinkingStyle, color: OffRecordColor.brandLavenderDark)
            }

            // Trait bars
            ForEach(Array(profile.traits.enumerated()), id: \.offset) { _, trait in
                traitRow(trait)
            }

            // Signature words
            if !profile.signatureWords.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR WORDS")
                        .font(OffRecordTypography.badgeLabel)
                        .tracking(1.2)
                        .foregroundColor(OffRecordColor.textInverse.opacity(0.82))

                    HStack(spacing: 8) {
                        ForEach(profile.signatureWords, id: \.self) { word in
                            Text(word)
                                .font(OffRecordTypography.metadata.monospaced())
                                .foregroundColor(OffRecordColor.textInverse)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(OffRecordColor.brandAqua.opacity(0.15))
                                .cornerRadius(6)
                        }
                    }
                }
            }

            // Stats row
            HStack(spacing: 0) {
                miniStat(value: profile.peakTime, label: String(localized: "Peak Time", comment: "Hour the user journals most"))
                miniStat(value: profile.dominantMood, label: String(localized: "Top Mood"))
                miniStat(value: profile.emotionalRange, label: String(localized: "Range", comment: "How widely the user’s mood varies"))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            OffRecordColor.brandPlum,
                            OffRecordColor.darkSurface
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(OffRecordColor.brandAqua.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func styleBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(OffRecordTypography.badgeLabel)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15))
            .cornerRadius(8)
    }

    private func traitRow(_ trait: FridayProfile.Trait) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(trait.label)
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textInverse.opacity(0.78))
                Spacer()
                Text(trait.displayLabel)
                    .font(OffRecordTypography.labelSmall)
                    .foregroundColor(OffRecordColor.textInverse.opacity(0.8))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(OffRecordColor.textInverse.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [OffRecordColor.brandAqua, OffRecordColor.brandLavender],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * max(0.05, min(1, trait.value)))
                }
            }
            .frame(height: 6)
            HStack {
                Text(trait.lowLabel)
                    .font(OffRecordTypography.annotation)
                    .foregroundColor(OffRecordColor.textInverse.opacity(0.62))
                Spacer()
                Text(trait.highLabel)
                    .font(OffRecordTypography.annotation)
                    .foregroundColor(OffRecordColor.textInverse.opacity(0.62))
            }
        }
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(OffRecordTypography.numberSmall)
                .foregroundColor(OffRecordColor.textInverse)
            Text(label)
                .font(OffRecordTypography.annotation)
                .foregroundColor(OffRecordColor.textInverse.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Export Card (for sharing as image)

private struct FridayProfileCardExport: View {
    let profile: FridayProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "person.text.rectangle")
                    .font(OffRecordExportTypography.label)
                Text("My Personality Card")
                    .font(OffRecordExportTypography.label)
                    .textCase(.uppercase)
                    .tracking(1.0)
            }
            .foregroundColor(OffRecordColor.brandAqua)

            // Style labels
            HStack(spacing: 10) {
                exportBadge(profile.communicationStyle, color: OffRecordColor.brandAqua)
                exportBadge(profile.thinkingStyle, color: OffRecordColor.brandLavenderDark)
            }

            // Traits
            ForEach(Array(profile.traits.enumerated()), id: \.offset) { _, trait in
                exportTraitRow(trait)
            }

            // Signature words
            if !profile.signatureWords.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MY WORDS")
                        .font(OffRecordExportTypography.label)
                        .tracking(1.2)
                        .foregroundColor(OffRecordColor.textInverse.opacity(0.78))

                    HStack(spacing: 8) {
                        ForEach(profile.signatureWords, id: \.self) { word in
                            Text(word)
                                .font(OffRecordExportTypography.monospaced)
                                .foregroundColor(OffRecordColor.textInverse)
                        }
                    }
                }
            }

            Spacer()

            // Stats
            HStack(spacing: 0) {
                exportStat(value: profile.peakTime, label: String(localized: "Peak Time", comment: "Hour the user journals most"))
                exportStat(value: profile.dominantMood, label: String(localized: "Top Mood"))
                exportStat(value: profile.emotionalRange, label: String(localized: "Range", comment: "How widely the user’s mood varies"))
                exportStat(value: "\(profile.totalEntries)", label: String(localized: "Entries", comment: "Number of journal entries"))
            }

            // Branding
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OffRecord")
                        .font(OffRecordExportTypography.brand)
                        .foregroundColor(OffRecordColor.textInverse.opacity(0.78))
                    Text("Private voice journal")
                        .font(OffRecordExportTypography.micro)
                        .foregroundColor(OffRecordColor.textInverse.opacity(0.68))
                }
                Spacer()
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            OffRecordColor.brandPlum,
                            OffRecordColor.darkSurface
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(OffRecordColor.brandAqua.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func exportBadge(_ text: String, color: Color) -> some View {
            Text(text)
                .font(OffRecordExportTypography.label)
                .foregroundColor(OffRecordColor.textInverse)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .cornerRadius(10)
    }

    private func exportTraitRow(_ trait: FridayProfile.Trait) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(trait.label)
                    .font(OffRecordExportTypography.metadata)
                    .foregroundColor(OffRecordColor.textInverse.opacity(0.78))
                Spacer()
                Text(trait.displayLabel)
                    .font(OffRecordExportTypography.label)
                    .foregroundColor(OffRecordColor.textInverse.opacity(0.85))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(OffRecordColor.textInverse.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [OffRecordColor.brandAqua, OffRecordColor.brandLavender], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * max(0.05, min(1, trait.value)))
                }
            }
            .frame(height: 6)
        }
    }

    private func exportStat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(OffRecordExportTypography.brand)
                .foregroundColor(OffRecordColor.textInverse)
            Text(label)
                .font(OffRecordExportTypography.micro)
                .foregroundColor(OffRecordColor.textInverse.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        FridayProfileCardContent(profile: FridayProfile(
            traits: [
                .init(label: "Expression", value: 0.7, lowLabel: "Reserved", highLabel: "Expressive", displayLabel: "Expressive"),
                .init(label: "Directness", value: 0.8, lowLabel: "Nuanced", highLabel: "Direct", displayLabel: "Direct"),
                .init(label: "Thinking", value: 0.3, lowLabel: "Intuitive", highLabel: "Analytical", displayLabel: "Intuitive"),
                .init(label: "Time Focus", value: 0.6, lowLabel: "Past", highLabel: "Future", displayLabel: "Future-focused"),
                .init(label: "Mindset", value: 0.75, lowLabel: "Fixed", highLabel: "Growth", displayLabel: "Growth"),
            ],
            signatureWords: ["maybe", "honestly", "actually", "weird", "literally"],
            peakTime: "11pm",
            totalEntries: 47,
            totalWords: 12840,
            dominantMood: "Anxious",
            emotionalRange: "Wide",
            communicationStyle: "Casual & Expressive",
            thinkingStyle: "Creative Dreamer",
            topPerson: "Sarah",
            topTopic: "Work",
            maturityLevel: "Developing"
        ))
        .padding()
    }
    .background(OffRecordColor.backgroundPrimary)
}
