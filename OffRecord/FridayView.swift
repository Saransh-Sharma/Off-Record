//
//  FridayView.swift
//  OffRecord
//
//  Friday - a private AI assistant for reflection and journaling.
//  All data stays on-device.
//

import SwiftUI

struct FridayView: View {
    @ObservedObject private var assistant = FridayAssistantEngine.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedSection: FridaySection = .overview
    @State private var showingDetail = false
    @State private var animateMascot = false
    @State private var showFridayShareSheet = false
    @State private var fridayShareImage: UIImage?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)],
        animation: .default)
    private var entries: FetchedResults<DiaryEntry>

    private var isIPad: Bool { horizontalSizeClass == .regular }

    enum FridaySection: String, CaseIterable {
        case overview = "Overview"
        case personality = "Personality"
        case emotions = "Emotions"
        case world = "My World"
        case patterns = "Patterns"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                fridayHeader

                talkToFridayButton

                // Maturity indicator
                maturityBadge

                // Section Picker
                sectionPicker

                // Content based on selection
                switch selectedSection {
                case .overview:
                    overviewSection
                case .personality:
                    personalitySection
                case .emotions:
                    emotionsSection
                case .world:
                    worldSection
                case .patterns:
                    patternsSection
                }

                // Privacy badge
                privacyBadge
            }
            .padding()
            .frame(maxWidth: isIPad ? 700 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Friday")
        .background(OffRecordColor.appBackgroundGradient.ignoresSafeArea())
        .onAppear { animateMascot = true }
    }

    // MARK: - Friday Header

    private var fridayHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                orbColor.opacity(0.3),
                                orbColor.opacity(0.1),
                                .clear
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                    .scaleEffect(animateMascot ? 1.04 : 0.98)

                FridayMascotView(pose: .idle, size: 132)
                    .shadow(color: orbColor.opacity(0.28), radius: 18, y: 8)
            }

            Text("Friday")
                .font(OffRecordTypography.titleMedium)
                .foregroundColor(OffRecordColor.textHeading)

            Text(assistant.summary.maturityLevel.description)
                .font(OffRecordTypography.bodyMedium)
                .foregroundColor(OffRecordColor.textSecondary)

            Text("A private AI assistant you can confide in.")
                .font(OffRecordTypography.bodySmall)
                .foregroundColor(OffRecordColor.textSecondary)
        }
    }

    // MARK: - Talk to Friday Button

    private var talkToFridayButton: some View {
        NavigationLink(destination: FridayChatView()) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(OffRecordColor.backgroundLavenderTint)
                        .frame(width: 32, height: 32)

                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(OffRecordColor.textLavender)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Talk to Friday")
                        .font(.subheadline.bold())
                        .foregroundColor(OffRecordColor.textHeading)
                    Text("Ask what she has noticed in your journal")
                        .font(.caption)
                        .foregroundColor(OffRecordColor.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(OffRecordColor.textSecondary)
            }
            .padding()
            .offRecordGlassControl(
                tint: OffRecordColor.brandLavenderDark,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                fallbackFill: OffRecordColor.surfaceLavender
            )
        }
    }

    // MARK: - Orb Color (reflects emotional state)

    private var orbColor: Color {
        let valence = assistant.emotionalSignature.baselineValence
        if valence > 0.3 { return OffRecordColor.brandMint }
        if valence > 0.1 { return OffRecordColor.brandAqua }
        if valence > -0.1 { return OffRecordColor.brandLavender }
        if valence > -0.3 { return OffRecordColor.brandPeach }
        return OffRecordColor.brandBlush
    }

    // MARK: - Maturity Badge

    private var maturityBadge: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(OffRecordColor.borderSoft)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [OffRecordColor.brandLavenderDark, OffRecordColor.brandAqua, OffRecordColor.brandLavender.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * assistant.summary.maturityLevel.progress, height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(assistant.summary.dataPointsCollected) data points")
                    .font(.caption)
                    .foregroundColor(OffRecordColor.textSecondary)
                Spacer()
                Text(assistant.summary.maturityLevel.rawValue.capitalized)
                    .font(.caption.bold())
                    .foregroundColor(OffRecordColor.textLavender)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(FridaySection.allCases, id: \.self) { section in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedSection = section
                        }
                    } label: {
                        Text(section.rawValue)
                            .font(.subheadline.weight(selectedSection == section ? .bold : .regular))
                            .foregroundColor(selectedSection == section ? OffRecordReadableTintStyle.friday.foreground : OffRecordColor.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .offRecordGlassControl(
                                tint: selectedSection == section ? OffRecordReadableTintStyle.friday.tint : nil,
                                in: Capsule(),
                                fallbackFill: selectedSection == section ? OffRecordReadableTintStyle.friday.fill : OffRecordReadableTintStyle.neutral.fill,
                                border: selectedSection == section ? OffRecordReadableTintStyle.friday.border : OffRecordReadableTintStyle.neutral.border
                            )
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
        VStack(spacing: 16) {
            // Friday Predictions — "Friday noticed..."
            FridayPredictionsSection(entries: Array(entries))

            // Shareable Personality Card
            FridayProfileCardSection()

            if !assistant.summary.personalitySnapshot.isEmpty {
                insightCard(title: "Who You Are", icon: "person.fill", content: assistant.summary.personalitySnapshot)
            }
            if !assistant.summary.communicationSnapshot.isEmpty {
                insightCard(title: "How You Express", icon: "text.bubble.fill", content: assistant.summary.communicationSnapshot)
            }
            if !assistant.summary.emotionalSnapshot.isEmpty {
                insightCard(title: "How You Feel", icon: "heart.fill", content: assistant.summary.emotionalSnapshot)
            }
            if !assistant.summary.lifeSnapshot.isEmpty {
                insightCard(title: "Your World", icon: "globe", content: assistant.summary.lifeSnapshot)
            }
            if !assistant.summary.growthSnapshot.isEmpty {
                insightCard(title: "Your Growth", icon: "arrow.up.right", content: assistant.summary.growthSnapshot)
            }

            if assistant.summary.dataPointsCollected < 5 {
                emptyStateCard
            }
        }
    }

    // MARK: - Personality Section

    private var personalitySection: some View {
        VStack(spacing: 16) {
            // Communication Style
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Communication Style", icon: "text.quote")

                traitBar(label: "Expressiveness", value: assistant.communicationStyle.expressiveness, lowLabel: "Reserved", highLabel: "Expressive")
                traitBar(label: "Directness", value: assistant.communicationStyle.directness, lowLabel: "Nuanced", highLabel: "Direct")
                traitBar(label: "Formality", value: assistant.communicationStyle.formalityLevel, lowLabel: "Casual", highLabel: "Formal")
            }
            .padding()
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)

            // Thinking Style
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Thinking Style", icon: "brain")

                traitBar(label: "Processing", value: assistant.thoughtPatterns.analyticalScore, lowLabel: "Intuitive", highLabel: "Analytical")
                traitBar(label: "Abstraction", value: assistant.thoughtPatterns.abstractScore, lowLabel: "Concrete", highLabel: "Abstract")
                traitBar(label: "Time Focus", value: assistant.thoughtPatterns.futureOriented, lowLabel: "Past", highLabel: "Future")
                traitBar(label: "Perspective", value: assistant.thoughtPatterns.selfFocused, lowLabel: "Others", highLabel: "Self")
            }
            .padding()
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)

            // Growth Indicators
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Growth Indicators", icon: "arrow.up.heart.fill")

                traitBar(label: "Growth Mindset", value: assistant.thoughtPatterns.growthMindsetScore, lowLabel: "Fixed", highLabel: "Growth")
                traitBar(label: "Self-Awareness", value: assistant.thoughtPatterns.selfAwarenessLevel, lowLabel: "Developing", highLabel: "Deep")
                traitBar(label: "Gratitude", value: assistant.thoughtPatterns.gratitudeTendency, lowLabel: "Occasional", highLabel: "Frequent")
            }
            .padding()
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)

            // Signature Words
            if !assistant.communicationStyle.signatureWords.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Your Vocabulary", icon: "textformat")

                    let topWords = assistant.communicationStyle.signatureWords
                        .sorted { $0.value > $1.value }
                        .prefix(15)

                    FlowLayout(spacing: 8) {
                        ForEach(Array(topWords), id: \.key) { word, count in
                            Text(word)
                                .font(.caption.weight(count > 3 ? .bold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(OffRecordColor.backgroundLavenderTint)
                                .foregroundColor(OffRecordColor.textLavender)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(OffRecordReadableTintStyle.friday.border, lineWidth: 1)
                                )
                                .cornerRadius(12)
                        }
                    }
                }
                .padding()
                .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceLavender)
            }

            // Share a personality card only after Friday has enough context.
            if assistant.behavioralPatterns.totalEntries >= 10 {
                shareFridayButton
            }
        }
        .sheet(isPresented: $showFridayShareSheet) {
            if let image = fridayShareImage {
                ShareSheet(activityItems: [
                    image,
                    PersonalityCardRenderer.shareText
                ])
            }
        }
    }

    // MARK: - Share Personality Card Button

    private var shareFridayButton: some View {
        Button {
            shareFridayCard()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share Your Personality Card")
                        .font(.system(size: 15, weight: .bold))
                    Text("A snapshot of the patterns Friday has noticed")
                        .font(.caption)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(OffRecordColor.textSecondary)
            }
            .foregroundColor(OffRecordColor.textPrimary)
            .padding(16)
            .offRecordGlassControl(
                tint: OffRecordColor.brandAqua,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                fallbackFill: OffRecordColor.surfaceMint
            )
        }
    }

    private func shareFridayCard() {
        Task { @MainActor in
            let profile = FridayProfileGenerator.generate()
            if let image = PersonalityCardRenderer.renderCard(profile: profile, format: .story) {
                fridayShareImage = image
                showFridayShareSheet = true
            }
        }
    }

    // MARK: - Emotions Section

    private var emotionsSection: some View {
        VStack(spacing: 16) {
            // Emotional Baseline
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Emotional Baseline", icon: "heart.circle.fill")

                HStack(spacing: 20) {
                    emotionMeter(label: "Valence", value: (assistant.emotionalSignature.baselineValence + 1) / 2, color: assistant.emotionalSignature.baselineValence > 0 ? OffRecordColor.brandMint : OffRecordColor.brandPeach)
                    emotionMeter(label: "Arousal", value: assistant.emotionalSignature.baselineArousal, color: OffRecordColor.brandSky)
                    emotionMeter(label: "Range", value: assistant.emotionalSignature.emotionalRange, color: OffRecordColor.brandAqua)
                }

                if assistant.emotionalSignature.sentimentTrend != 0 {
                    HStack {
                        Image(systemName: assistant.emotionalSignature.sentimentTrend > 0 ? "arrow.up.right" : "arrow.down.right")
                            .foregroundColor(sentimentTextColor(assistant.emotionalSignature.sentimentTrend))
                        Text("Emotional trajectory is \(assistant.emotionalSignature.sentimentTrend > 0 ? "improving" : "declining")")
                            .font(.caption)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                }
            }
            .padding()
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceBlush)

            // Time-Based Mood
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Mood Rhythms", icon: "clock.fill")

                HStack(spacing: 0) {
                    moodTimeBlock(label: "Morning", sentiment: assistant.emotionalSignature.morningMood, icon: "sunrise.fill")
                    moodTimeBlock(label: "Evening", sentiment: assistant.emotionalSignature.eveningMood, icon: "sunset.fill")
                    moodTimeBlock(label: "Weekday", sentiment: assistant.emotionalSignature.weekdayMood, icon: "briefcase.fill")
                    moodTimeBlock(label: "Weekend", sentiment: assistant.emotionalSignature.weekendMood, icon: "figure.walk")
                }
            }
            .padding()
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)

            // Mood Frequency
            if !assistant.emotionalSignature.emotionFrequency.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Emotion Frequency", icon: "chart.bar.fill")

                    let sorted = assistant.emotionalSignature.emotionFrequency.sorted { $0.value > $1.value }
                    let maxVal = sorted.first?.value ?? 1

                    ForEach(sorted.prefix(6), id: \.key) { mood, count in
                        HStack {
                            Text(moodEmoji(mood))
                            Text(mood.capitalized)
                                .font(.caption)
                                .frame(width: 60, alignment: .leading)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(moodColor(mood))
                                    .frame(width: geo.size.width * (count / maxVal))
                            }
                            .frame(height: 16)
                            Text("\(Int(count))")
                                .font(.caption)
                                .foregroundColor(OffRecordColor.textSecondary)
                        }
                    }
                }
                .padding()
                .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)
            }

            // Positive & Negative Triggers
            if !assistant.emotionalSignature.positiveTriggersTopics.isEmpty || !assistant.emotionalSignature.negativeTriggersTopics.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Emotional Triggers", icon: "bolt.heart.fill")

                    if !assistant.emotionalSignature.positiveTriggersTopics.isEmpty {
                        Text("Lifts your mood")
                            .font(.caption.bold())
                            .foregroundColor(OffRecordColor.textSage)

                        FlowLayout(spacing: 6) {
                            ForEach(Array(assistant.emotionalSignature.positiveTriggersTopics.sorted { $0.value > $1.value }.prefix(8)), id: \.key) { topic, _ in
                                Text(topic.capitalized)
                                    .font(.caption)
                                    .foregroundColor(OffRecordColor.textSage)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(OffRecordColor.backgroundSageTint)
                                    .cornerRadius(8)
                            }
                        }
                    }

                    if !assistant.emotionalSignature.negativeTriggersTopics.isEmpty {
                        Text("Weighs on you")
                            .font(.caption.bold())
                            .foregroundColor(OffRecordColor.textPeach)
                            .padding(.top, 4)

                        FlowLayout(spacing: 6) {
                            ForEach(Array(assistant.emotionalSignature.negativeTriggersTopics.sorted { $0.value > $1.value }.prefix(8)), id: \.key) { topic, _ in
                                Text(topic.capitalized)
                                    .font(.caption)
                                    .foregroundColor(OffRecordColor.textPeach)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(OffRecordColor.backgroundPeachTint)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
                .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)
            }
        }
    }

    // MARK: - World Section (Knowledge Graph)

    private var worldSection: some View {
        VStack(spacing: 16) {
            // People
            knowledgeSection(title: "People In Your Life", icon: "person.2.fill", type: .person)

            // Places
            knowledgeSection(title: "Places That Matter", icon: "mappin.circle.fill", type: .place)

            // Topics
            knowledgeSection(title: "Themes & Topics", icon: "tag.fill", type: .topic)

            // Goals
            knowledgeSection(title: "Your Goals", icon: "star.fill", type: .goal)

            // Fears
            knowledgeSection(title: "What Concerns You", icon: "exclamationmark.triangle.fill", type: .fear)

            if assistant.knowledgeGraph.nodes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: 40))
                        .foregroundColor(OffRecordColor.textLavender)
                    Text("Your world map will build as you journal")
                        .font(.subheadline)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)
            }
        }
    }

    // MARK: - Patterns Section

    private var patternsSection: some View {
        VStack(spacing: 16) {
            // Activity Heatmap
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("When You Write", icon: "clock.fill")

                // Hourly distribution
                let maxHourly = Double(assistant.behavioralPatterns.hourlyActivity.values.max() ?? 1)

                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<24, id: \.self) { hour in
                        let count = Double(assistant.behavioralPatterns.hourlyActivity[hour] ?? 0)
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(OffRecordColor.brandAqua.opacity(count / max(1, maxHourly)))
                                .frame(height: max(4, 60 * (count / max(1, maxHourly))))

                            if hour % 6 == 0 {
                                Text("\(hour)")
                                    .font(.system(size: 8))
                                    .foregroundColor(OffRecordColor.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: 80)

                if let peak = assistant.behavioralPatterns.peakHour {
                    Text("Peak writing time: \(formatHour(peak))")
                        .font(.caption)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
            }
            .padding()
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)

            // Day of Week
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Your Week", icon: "calendar")

                let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                let maxDaily = Double(assistant.behavioralPatterns.dayOfWeekActivity.values.max() ?? 1)

                HStack(spacing: 8) {
                    ForEach(1...7, id: \.self) { day in
                        let count = Double(assistant.behavioralPatterns.dayOfWeekActivity[day] ?? 0)
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(OffRecordColor.brandSky.opacity(count / max(1, maxDaily) * 0.8 + 0.1))
                                .frame(height: max(8, 50 * (count / max(1, maxDaily))))

                            Text(days[day - 1])
                                .font(.system(size: 10))
                                .foregroundColor(OffRecordColor.textSecondary)
                        }
                    }
                }
                .frame(height: 70)
            }
            .padding()
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceBlue)

            // Writing Stats
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Writing Stats", icon: "doc.text.fill")

                HStack(spacing: 20) {
                    statItem(value: "\(assistant.behavioralPatterns.totalEntries)", label: "Entries")
                    statItem(value: formatNumber(assistant.behavioralPatterns.totalWords), label: "Words")
                    statItem(value: "\(Int(assistant.communicationStyle.averageSentenceLength))", label: "Avg Sentence")
                    statItem(value: String(format: "%.0f%%", assistant.communicationStyle.vocabularyRichness * 100), label: "Vocab Richness")
                }
            }
            .padding()
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)

            // Preferences
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Your Preferences", icon: "slider.horizontal.3")

                traitBar(label: "Input Mode", value: assistant.behavioralPatterns.prefersVoice, lowLabel: "Text", highLabel: "Voice")
                traitBar(label: "Entry Length", value: 1 - assistant.behavioralPatterns.prefersShortEntries, lowLabel: "Brief", highLabel: "Detailed")
            }
            .padding()
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)
        }
    }

    // MARK: - Reusable Components

    private func insightCard(title: String, icon: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(OffRecordColor.textLavender)
                Text(title)
                    .font(.headline)
                    .foregroundColor(OffRecordColor.textHeading)
            }
            Text(content)
                .font(.subheadline)
                .foregroundColor(OffRecordColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceLavender)
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(OffRecordColor.textLavender)
            Text(title)
                .font(.headline)
                .foregroundColor(OffRecordColor.textHeading)
        }
    }

    private func traitBar(label: String, value: Double, lowLabel: String, highLabel: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(OffRecordColor.textSecondary)
                Spacer()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(OffRecordColor.textTertiary.opacity(0.18))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [OffRecordColor.brandLavenderDark, OffRecordColor.brandAqua],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * max(0.05, min(1, value)))
                }
            }
            .frame(height: 8)
            HStack {
                Text(lowLabel)
                    .font(.system(size: 9))
                    .foregroundColor(OffRecordColor.textSecondary)
                Spacer()
                Text(highLabel)
                    .font(.system(size: 9))
                    .foregroundColor(OffRecordColor.textSecondary)
            }
        }
    }

    private func emotionMeter(label: String, value: Double, color: Color) -> some View {
        let meterSize: CGFloat = isIPad ? 70 : 50
        let lineWidth: CGFloat = isIPad ? 6 : 4
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(OffRecordColor.textTertiary.opacity(0.2), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.05, value))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text(String(format: "%.0f%%", value * 100))
                    .font(.system(size: isIPad ? 14 : 11, weight: .bold))
                    .foregroundColor(OffRecordColor.textPrimary)
            }
            .frame(width: meterSize, height: meterSize)

            Text(label)
                .font(.system(size: isIPad ? 12 : 10))
                .foregroundColor(OffRecordColor.textSecondary)
        }
    }

    private func moodTimeBlock(label: String, sentiment: Double, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(sentimentColor(sentiment))
                .font(.title3)

            Text(sentimentLabel(sentiment))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(sentimentTextColor(sentiment))

            Text(label)
                .font(.system(size: 9))
                .foregroundColor(OffRecordColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func knowledgeSection(title: String, icon: String, type: PersonalKnowledgeGraph.KnowledgeNode.NodeType) -> some View {
        let nodes = assistant.knowledgeGraph.topNodes(ofType: type, limit: 8)
        return Group {
            if !nodes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(title, icon: icon)

                    ForEach(nodes, id: \.id) { node in
                        HStack {
                            Circle()
                                .fill(sentimentColor(node.sentimentAssociation))
                                .frame(width: 8, height: 8)

                            Text(node.label)
                                .font(.subheadline)
                                .foregroundColor(OffRecordColor.textPrimary)

                            Spacer()

                            Text("\(node.mentions)x")
                                .font(.caption)
                                .foregroundColor(OffRecordColor.textSecondary)

                            // Importance indicator
                            HStack(spacing: 1) {
                                ForEach(0..<5, id: \.self) { i in
                                    Circle()
                                        .fill(Double(i) / 5.0 < node.importance ? OffRecordColor.brandLavenderDark : OffRecordColor.textTertiary.opacity(0.2))
                                        .frame(width: 4, height: 4)
                                }
                            }
                        }
                    }
                }
                .padding()
                .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)
            }
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundColor(OffRecordColor.textLavender)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(OffRecordColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            FridayMascotView(pose: .wave, size: 92)

            Text("Friday is getting to know you")
                .font(.headline)
                .foregroundColor(OffRecordColor.textHeading)

            Text("Keep journaling with OffRecord AI Journal. Friday learns from every entry and starts noticing the patterns that matter.")
                .font(.subheadline)
                .foregroundColor(OffRecordColor.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Label("Voice entries", systemImage: "mic.fill")
                Label("Written entries", systemImage: "square.and.pencil")
            }
            .font(.caption)
            .foregroundColor(OffRecordColor.textLavender)
        }
        .padding(24)
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceSage)
    }

    private var privacyBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(OffRecordReadableTintStyle.privacy.foreground)
            Text("Friday runs on-device. Your journal never leaves your device.")
                .font(.caption)
                .foregroundColor(OffRecordReadableTintStyle.privacy.foreground)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .offRecordGlassControl(
            tint: OffRecordReadableTintStyle.privacy.tint,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous),
            fallbackFill: OffRecordReadableTintStyle.privacy.fill,
            border: OffRecordReadableTintStyle.privacy.border
        )
    }

    // MARK: - Helpers

    private func sentimentColor(_ sentiment: Double) -> Color {
        if sentiment > 0.3 { return OffRecordColor.brandMint }
        if sentiment > 0.1 { return OffRecordColor.brandAqua }
        if sentiment > -0.1 { return OffRecordColor.textTertiary }
        if sentiment > -0.3 { return OffRecordColor.brandPeach }
        return OffRecordColor.brandCoral
    }

    private func sentimentTextColor(_ sentiment: Double) -> Color {
        if sentiment > 0.3 { return OffRecordColor.textMint }
        if sentiment > 0.1 { return OffRecordColor.textAqua }
        if sentiment > -0.1 { return OffRecordColor.textSecondary }
        if sentiment > -0.3 { return OffRecordColor.textPeach }
        return OffRecordColor.textCoral
    }

    private func sentimentLabel(_ sentiment: Double) -> String {
        if sentiment > 0.3 { return "Great" }
        if sentiment > 0.1 { return "Good" }
        if sentiment > -0.1 { return "Neutral" }
        if sentiment > -0.3 { return "Low" }
        return "Tough"
    }

    private func moodEmoji(_ mood: String) -> String {
        switch mood.lowercased() {
        case "happy": return "😊"
        case "calm": return "😌"
        case "grateful": return "🙏"
        case "excited": return "🤩"
        case "tired": return "😴"
        case "anxious": return "😰"
        case "sad": return "😢"
        case "angry": return "😤"
        default: return "😐"
        }
    }

    private func moodColor(_ mood: String) -> Color {
        switch mood.lowercased() {
        case "happy": return OffRecordColor.brandYellow
        case "calm": return OffRecordColor.brandAqua
        case "grateful": return OffRecordColor.brandMint
        case "excited": return OffRecordColor.brandPeach
        case "tired": return OffRecordColor.textTertiary
        case "anxious": return OffRecordColor.brandLavender
        case "sad": return OffRecordColor.brandSky
        case "angry": return OffRecordColor.brandCoral
        default: return OffRecordColor.textTertiary
        }
    }

    private func formatHour(_ hour: Int) -> String {
        if hour == 0 { return "12am" }
        if hour < 12 { return "\(hour)am" }
        if hour == 12 { return "12pm" }
        return "\(hour - 12)pm"
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1000 {
            return String(format: "%.1fk", Double(n) / 1000)
        }
        return "\(n)"
    }
}

// MARK: - Flow Layout (for word clouds)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}

#Preview {
    NavigationView {
        FridayView()
    }
}
