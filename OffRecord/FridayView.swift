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
    @ObservedObject private var navigationRouter = OffRecordNavigationRouter.shared
    @ObservedObject private var memoryPreferences = FridayMemoryPreferences.shared
    @State private var selectedSection: FridaySection = .overview
    @State private var selectedMemoryNode: PersonalKnowledgeGraph.KnowledgeNode?
    @State private var noteEntry: DiaryEntry?
    @State private var isShowingPromptNote = false
    @State private var promptNoteContext: String?
    @State private var shouldDeleteEmptyNoteDraft = false
    @State private var routedFridayQuestion: String?
    @State private var fridayActivity: NSUserActivity?
    @State private var promptNoteError: String?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)],
        animation: .default)
    private var entries: FetchedResults<DiaryEntry>

    private var isIPad: Bool { horizontalSizeClass == .regular }
    private var startedEntries: [DiaryEntry] { entries.startedEntries }

    enum FridaySection: String, CaseIterable {
        case overview = "Overview"
        case personality = "Personality"
        case emotions = "Emotions"
        case world = "My World"

        /// Shown in the UI. The raw value is only an identifier.
        var title: String {
            switch self {
            case .overview: return String(localized: "Overview", comment: "Friday screen section tab")
            case .personality: return String(localized: "Personality", comment: "Friday screen section tab")
            case .emotions: return String(localized: "Emotions", comment: "Friday screen section tab")
            case .world: return String(localized: "My World", comment: "Friday screen section tab: people, places, and topics Friday remembers")
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = OffRecordAdaptiveMetrics(
                width: proxy.size.width,
                horizontalSizeClass: horizontalSizeClass
            )

            ScrollView {
                if metrics.mode.supportsSupplementaryPanels {
                    expandedFridayLayout(metrics: metrics)
                } else {
                    phoneFirstFridayLayout(metrics: metrics)
                }
            }
        }
        .navigationTitle(Text("Friday", comment: "Name of the in-app assistant"))
        .background(OffRecordAppBackground().ignoresSafeArea())
        .onAppear {
            startFridayPredictionActivity()
            applyRoutedFridayQuestion(navigationRouter.fridayQuestion)
        }
        .onDisappear {
            fridayActivity?.resignCurrent()
            fridayActivity = nil
        }
        .onChange(of: navigationRouter.fridayQuestion) { _, question in
            applyRoutedFridayQuestion(question)
        }
        .sensoryFeedback(.selection, trigger: selectedSection)
        .sheet(item: $selectedMemoryNode) { node in
            FridayMemoryDetailSheet(node: node)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: $isShowingPromptNote) {
            if let noteEntry {
                EntryDetailView(
                    entry: noteEntry,
                    startEditing: true,
                    deleteEmptyDraftOnDisappear: shouldDeleteEmptyNoteDraft,
                    promptContext: promptNoteContext
                )
            }
        }
        .alert("Couldn’t Open Entry", isPresented: Binding(
            get: { promptNoteError != nil },
            set: { if !$0 { promptNoteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(promptNoteError ?? "")
        }
        .navigationDestination(isPresented: Binding(
            get: { routedFridayQuestion != nil },
            set: { isPresented in
                if !isPresented {
                    navigationRouter.clearFridayQuestion(routedFridayQuestion)
                    routedFridayQuestion = nil
                }
            }
        )) {
            FridayChatView(
                initialQuestion: routedFridayQuestion,
                autoSubmitInitialQuestion: routedFridayQuestion?.isEmpty == false
            )
        }
    }

    private func phoneFirstFridayLayout(metrics: OffRecordAdaptiveMetrics) -> some View {
        VStack(spacing: 24) {
            fridayHeader
                .scrollTransition { content, phase in
                    content
                        .opacity(phase.isIdentity ? 1 : 0.6)
                        .scaleEffect(phase.isIdentity ? 1 : 0.92)
                }

            talkToFridayButton
            maturityBadge
            sectionPicker
            selectedFridayContent
        }
        .padding(.horizontal, metrics.pageHorizontalPadding)
        .padding(.vertical, 16)
        .frame(maxWidth: metrics.readableContentMaxWidth ?? .infinity)
        .frame(maxWidth: .infinity)
    }

    private func expandedFridayLayout(metrics: OffRecordAdaptiveMetrics) -> some View {
        HStack(alignment: .top, spacing: OffRecordSpacing.xxxl) {
            VStack(spacing: OffRecordSpacing.xl) {
                fridayHeader
                talkToFridayButton
                maturityBadge
                fridaySectionRail
            }
            .frame(width: 320)
            .padding(.top, OffRecordSpacing.lg)

            VStack(spacing: OffRecordSpacing.xl) {
                selectedFridayContent
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, metrics.pageHorizontalPadding)
        .padding(.vertical, OffRecordSpacing.xxl)
        .frame(maxWidth: metrics.pageMaxWidth ?? .infinity)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var selectedFridayContent: some View {
        switch selectedSection {
        case .overview:
            overviewSection
        case .personality:
            personalitySection
        case .emotions:
            emotionsSection
        case .world:
            worldSection
        }
    }

    private var fridaySectionRail: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            ForEach(FridaySection.allCases, id: \.self) { section in
                Button {
                    withOffRecordAnimation(OffRecordMotion.snappy) {
                        selectedSection = section
                    }
                } label: {
                    HStack {
                        Text(section.title)
                            .font(OffRecordTypography.labelMedium)
                        Spacer()
                        if selectedSection == section {
                            Image(systemName: "checkmark")
                                .font(OffRecordTypography.labelSmall)
                        }
                    }
                    .foregroundStyle(selectedSection == section ? OffRecordReadableTintStyle.friday.foreground : OffRecordColor.textPrimary)
                    .padding(.horizontal, OffRecordSpacing.lg)
                    .frame(minHeight: 46)
                    .background(
                        selectedSection == section ? OffRecordReadableTintStyle.friday.fill : OffRecordReadableTintStyle.neutral.fill,
                        in: RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous)
                            .stroke(selectedSection == section ? OffRecordReadableTintStyle.friday.border : OffRecordReadableTintStyle.neutral.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(section.title) section")
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                .offRecordPointerLift()
            }
        }
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
                    .modifier(FridayBreathingModifier())
                    .accessibilityHidden(true)

                FridayMascotView(pose: .idle, size: isIPad ? 132 : 110)
                    .shadow(color: orbColor.opacity(0.28), radius: 18, y: 8)
            }

            Text("Friday", comment: "Name of the in-app assistant")
                .font(OffRecordTypography.titleMedium)
                .foregroundColor(OffRecordColor.textHeading)

            Text(assistant.summary.maturityLevel.description)
                .font(OffRecordTypography.bodyMedium)
                .foregroundColor(OffRecordColor.textSecondary)

            Text("I learn from what you write.")
                .font(OffRecordTypography.bodySmall)
                .foregroundColor(OffRecordColor.textSecondary)
        }
    }

    // MARK: - Talk to Friday Button

    private var talkToFridayButton: some View {
        NavigationLink(destination: FridayChatView()) {
            HStack(spacing: 12) {
                OffRecordIconBubble(
                    systemImage: "bubble.left.and.bubble.right.fill",
                    tint: OffRecordColor.textLavender,
                    fill: OffRecordColor.backgroundLavenderTint,
                    size: 32,
                    iconSize: 13
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Talk to Friday")
                        .font(OffRecordTypography.labelMedium)
                        .foregroundColor(OffRecordColor.textHeading)
                    Text("Ask me about your journal.")
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)
            }
            .padding()
            .offRecordGlassControl(
                tint: OffRecordColor.brandLavenderDark,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                fallbackFill: OffRecordColor.surfaceLavender
            )
        }
        .accessibilityIdentifier("friday.talk")
    }

    private func applyRoutedFridayQuestion(_ question: String?) {
        let trimmed = question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        routedFridayQuestion = trimmed
    }

    private func startFridayPredictionActivity() {
        fridayActivity?.resignCurrent()
        fridayActivity = JournalSpotlightIndexer.shared.predictionActivity(
            type: "com.singularity.offrecord.friday",
            title: String(localized: "Talk to Friday"),
            route: .friday(question: nil)
        )
        fridayActivity?.becomeCurrent()
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("How Well I Know You")
            .accessibilityValue("\(Int((assistant.summary.maturityLevel.progress * 100).rounded())) percent, \(assistant.summary.maturityLevel.displayName), \(String(AttributedString(localized: "^[\(assistant.summary.dataPointsCollected) entry](inflect: true)").characters))")

            HStack {
                Text("^[\(assistant.summary.dataPointsCollected) entry](inflect: true)")
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)
                Spacer()
                Text(assistant.summary.maturityLevel.displayName)
                    .font(OffRecordTypography.labelSmall)
                    .foregroundColor(OffRecordColor.textLavender)
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal)
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(FridaySection.allCases, id: \.self) { section in
                    Button {
                        withOffRecordAnimation(OffRecordMotion.snappy) {
                            selectedSection = section
                        }
                    } label: {
                        Text(section.title)
                            .font(selectedSection == section ? OffRecordTypography.labelMedium : OffRecordTypography.bodySmall)
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
                    .accessibilityLabel("\(section.title) section")
                    .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
        VStack(spacing: 16) {
            // Proactive Reflection Loop ("From Friday" cards)
            ProactiveReflectionSection(entries: startedEntries) { insight in
                startPromptNote(from: insight)
            }

            // Shareable Personality Card
            FridayProfileCardSection()

            if !assistant.summary.personalitySnapshot.isEmpty {
                insightCard(title: String(localized: "Personality", comment: "Card heading: the user's personality"), icon: "person.fill", content: assistant.summary.personalitySnapshot)
            }
            if !assistant.summary.communicationSnapshot.isEmpty {
                insightCard(title: String(localized: "How You Write"), icon: "text.bubble.fill", content: assistant.summary.communicationSnapshot)
            }
            if !assistant.summary.emotionalSnapshot.isEmpty {
                insightCard(title: String(localized: "Mood", comment: "Card heading: the user's mood"), icon: "heart.fill", content: assistant.summary.emotionalSnapshot)
            }
            if !worldSnapshot.isEmpty {
                insightCard(title: String(localized: "People & Topics"), icon: "globe", content: worldSnapshot)
            }
            if !assistant.summary.growthSnapshot.isEmpty {
                insightCard(title: String(localized: "Growth", comment: "Card heading: how the user is growing"), icon: "arrow.up.right", content: assistant.summary.growthSnapshot)
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
                sectionHeader(String(localized: "How You Write"), icon: "text.quote")

                traitBar(label: String(localized: "Expressiveness"), value: assistant.communicationStyle.expressiveness, lowLabel: String(localized: "Reserved", comment: "Low end of the “Expressiveness” scale"), highLabel: String(localized: "Expressive", comment: "High end of the “Expressiveness” scale"))
                traitBar(label: String(localized: "Directness"), value: assistant.communicationStyle.directness, lowLabel: String(localized: "Nuanced", comment: "Low end of the “Directness” scale"), highLabel: String(localized: "Direct", comment: "High end of the “Directness” scale"))
                traitBar(label: String(localized: "Formality"), value: assistant.communicationStyle.formalityLevel, lowLabel: String(localized: "Casual", comment: "Low end of the “Formality” scale"), highLabel: String(localized: "Formal", comment: "High end of the “Formality” scale"))
            }
            .padding()
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)

            // Thinking Style
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(String(localized: "How You Think"), icon: "brain")

                traitBar(label: String(localized: "Processing", comment: "Trait scale: how the user processes things"), value: assistant.thoughtPatterns.analyticalScore, lowLabel: String(localized: "Intuitive", comment: "Low end of the “Processing” scale"), highLabel: String(localized: "Analytical", comment: "High end of the “Processing” scale"))
                traitBar(label: String(localized: "Abstraction"), value: assistant.thoughtPatterns.abstractScore, lowLabel: String(localized: "Concrete", comment: "Low end of the “Abstraction” scale"), highLabel: String(localized: "Abstract", comment: "High end of the “Abstraction” scale"))
                traitBar(label: String(localized: "Time Focus"), value: assistant.thoughtPatterns.futureOriented, lowLabel: String(localized: "Past", comment: "Low end of the “Time Focus” scale"), highLabel: String(localized: "Future", comment: "High end of the “Time Focus” scale"))
                traitBar(label: String(localized: "Perspective"), value: assistant.thoughtPatterns.selfFocused, lowLabel: String(localized: "Others", comment: "Low end of the “Perspective” scale"), highLabel: String(localized: "Self", comment: "High end of the “Perspective” scale"))
            }
            .padding()
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)

            // Growth Indicators
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(String(localized: "Growth", comment: "Card heading: how the user is growing"), icon: "arrow.up.heart.fill")

                traitBar(label: String(localized: "Growth Mindset"), value: assistant.thoughtPatterns.growthMindsetScore, lowLabel: String(localized: "Fixed", comment: "Low end of the “Growth Mindset” scale"), highLabel: String(localized: "Growth", comment: "High end of the “Growth Mindset” scale"))
                traitBar(label: String(localized: "Self-Awareness"), value: assistant.thoughtPatterns.selfAwarenessLevel, lowLabel: String(localized: "Developing", comment: "Low end of the “Self-Awareness” scale"), highLabel: String(localized: "Deep", comment: "High end of the “Self-Awareness” scale"))
                traitBar(label: String(localized: "Gratitude"), value: assistant.thoughtPatterns.gratitudeTendency, lowLabel: String(localized: "Occasional", comment: "Low end of the “Gratitude” scale"), highLabel: String(localized: "Frequent", comment: "High end of the “Gratitude” scale"))
            }
            .padding()
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)

            // Signature Words
            if !assistant.communicationStyle.signatureWords.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(String(localized: "Words You Use"), icon: "textformat")

                    let topWords = assistant.communicationStyle.signatureWords
                        .sorted { $0.value > $1.value }
                        .prefix(15)

                    FlowLayout(spacing: 8) {
                        ForEach(Array(topWords), id: \.key) { word, count in
                            Text(word)
                                .font(count > 3 ? OffRecordTypography.labelSmall : OffRecordTypography.metadata)
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
        }
    }

    // MARK: - Emotions Section

    private var emotionsSection: some View {
        VStack(spacing: 16) {
            // Emotional Baseline
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(String(localized: "Your Usual Mood"), icon: "heart.circle.fill")

                HStack(spacing: 20) {
                    emotionMeter(label: String(localized: "Mood", comment: "Meter label: the user's usual mood"), value: (assistant.emotionalSignature.baselineValence + 1) / 2, color: assistant.emotionalSignature.baselineValence > 0 ? OffRecordColor.brandMint : OffRecordColor.brandPeach)
                    emotionMeter(label: String(localized: "Energy", comment: "Meter label: the user's usual energy"), value: assistant.emotionalSignature.baselineArousal, color: OffRecordColor.brandSky)
                    emotionMeter(label: String(localized: "Range", comment: "Meter label: how widely the user's mood varies"), value: assistant.emotionalSignature.emotionalRange, color: OffRecordColor.brandAqua)
                }

                if assistant.emotionalSignature.sentimentTrend != 0 {
                    HStack {
                        Image(systemName: assistant.emotionalSignature.sentimentTrend > 0 ? "arrow.up.right" : "arrow.down.right")
                            .foregroundColor(sentimentTextColor(assistant.emotionalSignature.sentimentTrend))
                        Text(assistant.emotionalSignature.sentimentTrend > 0 ? "Your mood has been improving lately." : "Your mood has been dipping lately.")
                            .font(OffRecordTypography.metadata)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                }
            }
            .padding()
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceBlush)

            // Time-Based Mood
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(String(localized: "When You Feel Best"), icon: "clock.fill")

                HStack(spacing: 0) {
                    moodTimeBlock(label: String(localized: "Morning"), sentiment: assistant.emotionalSignature.morningMood, icon: "sunrise.fill")
                    moodTimeBlock(label: String(localized: "Evening"), sentiment: assistant.emotionalSignature.eveningMood, icon: "sunset.fill")
                    moodTimeBlock(label: String(localized: "Weekday"), sentiment: assistant.emotionalSignature.weekdayMood, icon: "briefcase.fill")
                    moodTimeBlock(label: String(localized: "Weekend"), sentiment: assistant.emotionalSignature.weekendMood, icon: "figure.walk")
                }
            }
            .padding()
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)

            // Mood Frequency
            if !assistant.emotionalSignature.emotionFrequency.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(String(localized: "Most Common Moods"), icon: "chart.bar.fill")

                    let sorted = assistant.emotionalSignature.emotionFrequency.sorted { $0.value > $1.value }
                    let maxVal = sorted.first?.value ?? 1

                    ForEach(sorted.prefix(6), id: \.key) { mood, count in
                        HStack {
                            MiniMoodIcon(
                                mood: Mood(rawEmotion: mood),
                                size: 18,
                                opacity: 0.86
                            )
                            Text(Mood(rawValue: mood)?.displayName ?? mood.capitalized)
                                .font(OffRecordTypography.metadata)
                                .frame(width: 60, alignment: .leading)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(moodColor(mood))
                                    .frame(width: geo.size.width * (count / maxVal))
                            }
                            .frame(height: 16)
                            Text("\(Int(count))")
                                .font(OffRecordTypography.metadata)
                                .foregroundColor(OffRecordColor.textSecondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Mood(rawValue: mood)?.displayName ?? mood.capitalized)
                        .accessibilityValue(String(AttributedString(localized: "^[\(Int(count)) entry](inflect: true)").characters))
                    }
                }
                .padding()
                .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)
            }

            // Positive & Negative Triggers
            if !assistant.emotionalSignature.positiveTriggersTopics.isEmpty || !assistant.emotionalSignature.negativeTriggersTopics.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(String(localized: "What Affects Your Mood"), icon: "bolt.heart.fill")

                    if !assistant.emotionalSignature.positiveTriggersTopics.isEmpty {
                        Text("Lifts Your Mood")
                            .font(OffRecordTypography.labelSmall)
                            .foregroundColor(OffRecordColor.textSage)

                        FlowLayout(spacing: 6) {
                            ForEach(Array(visibleTriggers(assistant.emotionalSignature.positiveTriggersTopics).prefix(8)), id: \.key) { topic, _ in
                                Text(topic.capitalized)
                                    .font(OffRecordTypography.metadata)
                                    .foregroundColor(OffRecordColor.textSage)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(OffRecordColor.backgroundSageTint)
                                    .cornerRadius(8)
                            }
                        }
                    }

                    if !assistant.emotionalSignature.negativeTriggersTopics.isEmpty {
                        Text("Weighs on You")
                            .font(OffRecordTypography.labelSmall)
                            .foregroundColor(OffRecordColor.textPeach)
                            .padding(.top, 4)

                        FlowLayout(spacing: 6) {
                            ForEach(Array(visibleTriggers(assistant.emotionalSignature.negativeTriggersTopics).prefix(8)), id: \.key) { topic, _ in
                                Text(topic.capitalized)
                                    .font(OffRecordTypography.metadata)
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
            if !assistant.knowledgeGraph.fridayVisibleNodes(limit: 1, preferences: memoryPreferences).isEmpty {
                VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                    Text("What I Remember")
                        .font(OffRecordTypography.titleSmall)
                        .foregroundStyle(OffRecordColor.textHeading)
                        .accessibilityAddTraits(.isHeader)
                    Text("Rename anything, or ask me to forget it.")
                        .font(OffRecordTypography.bodySmall)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // People
            knowledgeSection(title: String(localized: "People"), icon: "person.2.fill", type: .person)

            // Places
            knowledgeSection(title: String(localized: "Places"), icon: "mappin.circle.fill", type: .place)

            // Topics
            knowledgeSection(title: String(localized: "Topics"), icon: "tag.fill", type: .topic)

            // Goals
            knowledgeSection(title: String(localized: "Goals"), icon: "star.fill", type: .goal)

            // Fears
            knowledgeSection(title: String(localized: "Worries"), icon: "cloud.rain.fill", type: .fear)

            if !memoryPreferences.forgottenIDs.isEmpty {
                forgottenFooter
            }

            if assistant.knowledgeGraph.fridayVisibleNodes(limit: 1, preferences: memoryPreferences).isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(OffRecordTypography.displayXL)
                        .foregroundColor(OffRecordColor.textLavender)
                        .accessibilityHidden(true)
                    Text("People and places you mention will show up here.")
                        .font(OffRecordTypography.bodySmall)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)
            }
        }
    }

    // MARK: - Reusable Components

    private func insightCard(title: String, icon: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(OffRecordColor.textLavender)
                Text(title)
                    .font(OffRecordTypography.sectionTitle)
                    .foregroundColor(OffRecordColor.textHeading)
            }
            Text(content)
                .font(OffRecordTypography.bodySmall)
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
                .font(OffRecordTypography.sectionTitle)
                .foregroundColor(OffRecordColor.textHeading)
        }
    }

    private func traitBar(label: String, value: Double, lowLabel: String, highLabel: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(OffRecordTypography.metadata)
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
                    .font(OffRecordTypography.annotation)
                    .foregroundColor(OffRecordColor.textSecondary)
                Spacer()
                Text(highLabel)
                    .font(OffRecordTypography.annotation)
                    .foregroundColor(OffRecordColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value * 100)) percent, \(lowLabel) to \(highLabel)")
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

                Text(value, format: .percent.precision(.fractionLength(0)))
                    .font(OffRecordTypography.numberSmall)
                    .foregroundColor(OffRecordColor.textPrimary)
            }
            .frame(width: meterSize, height: meterSize)

            Text(label)
                .font(OffRecordTypography.annotation)
                .foregroundColor(OffRecordColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value * 100)) percent")
    }

    private func moodTimeBlock(label: String, sentiment: Double, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(sentimentColor(sentiment))
                .font(OffRecordTypography.titleSmall)

            Text(sentimentLabel(sentiment))
                .font(OffRecordTypography.labelSmall)
                .foregroundColor(sentimentTextColor(sentiment))

            Text(label)
                .font(OffRecordTypography.annotation)
                .foregroundColor(OffRecordColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(sentimentLabel(sentiment))
    }

    private func knowledgeSection(title: String, icon: String, type: PersonalKnowledgeGraph.KnowledgeNode.NodeType) -> some View {
        let nodes = assistant.knowledgeGraph.fridayVisibleNodes(ofType: type, limit: 8, preferences: memoryPreferences)
        return Group {
            if !nodes.isEmpty {
                VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
                    sectionHeader(title, icon: icon)
                        .padding(.bottom, OffRecordSpacing.xs)

                    ForEach(nodes, id: \.id) { node in
                        FridayMemoryRow(node: node) {
                            selectedMemoryNode = assistant.knowledgeGraph.nodes[node.id]
                        }
                    }
                }
                .padding()
                .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)
            }
        }
    }

    private var forgottenFooter: some View {
        HStack(spacing: OffRecordSpacing.md) {
            Image(systemName: "eye.slash")
                .foregroundStyle(OffRecordColor.textSecondary)
                .accessibilityHidden(true)
            Text("^[\(memoryPreferences.forgottenIDs.count) hidden item](inflect: true)")
                .font(OffRecordTypography.metadata)
                .foregroundStyle(OffRecordColor.textSecondary)
            Spacer(minLength: OffRecordSpacing.sm)
            Button("Restore") {
                withOffRecordAnimation {
                    memoryPreferences.restoreAll()
                }
            }
            .font(OffRecordTypography.labelSmall)
            .foregroundStyle(OffRecordColor.textLavender)
            .frame(minHeight: OffRecordLayout.minimumTapTarget)
            .accessibilityHint("Shows hidden items again.")
            .accessibilityIdentifier("friday.memory.restore")
        }
        .padding(.horizontal, OffRecordSpacing.lg)
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)
    }

    /// People and themes for the Overview card, honoring Forget and Rename.
    private var worldSnapshot: String {
        let people = assistant.knowledgeGraph.fridayVisibleNodes(ofType: .person, limit: 3, preferences: memoryPreferences)
        let topics = assistant.knowledgeGraph.fridayVisibleNodes(ofType: .topic, limit: 3, preferences: memoryPreferences)
        var items: [String] = []
        if !people.isEmpty {
            items.append(String(localized: "People: \(people.map(\.label).joined(separator: ", ")).", comment: "Followed by a comma-separated list of names"))
        }
        if !topics.isEmpty {
            items.append(String(localized: "Topics: \(topics.map(\.label).joined(separator: ", ")).", comment: "Followed by a comma-separated list of topics"))
        }
        return items.joined(separator: " ")
    }

    private func visibleTriggers(_ triggers: [String: Double]) -> [(key: String, value: Double)] {
        triggers
            .filter { !memoryPreferences.isForgottenLabel($0.key) }
            .sorted { $0.value > $1.value }
    }

    private var emptyStateCard: some View {
        EmptyStateView.fridayGettingToKnow
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceSage)
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
        if sentiment > 0.3 { return String(localized: "Great", comment: "How the user usually feels at this time") }
        if sentiment > 0.1 { return String(localized: "Good", comment: "How the user usually feels at this time") }
        if sentiment > -0.1 { return String(localized: "Neutral", comment: "How the user usually feels at this time") }
        if sentiment > -0.3 { return String(localized: "Low", comment: "How the user usually feels at this time") }
        return String(localized: "Tough", comment: "How the user usually feels at this time")
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

    private func startPromptNote(from insight: ReflectionInsight) {
        let hadEntry = todayEntry != nil
        guard let entry = getOrCreateTodayEntry() else { return }
        noteEntry = entry
        promptNoteContext = insight.prompt
        shouldDeleteEmptyNoteDraft = !hadEntry && entryHasNoContent(entry)
        isShowingPromptNote = true
        HapticManager.shared.selectionChanged()
    }

    private var todayEntry: DiaryEntry? {
        let calendar = Calendar.current
        return startedEntries.first { entry in
            guard let date = entry.date else { return false }
            return calendar.isDateInToday(date)
        }
    }

    private var todayDraftOrStartedEntry: DiaryEntry? {
        let calendar = Calendar.current
        return entries.first { entry in
            guard let date = entry.date else { return false }
            return calendar.isDateInToday(date)
        }
    }

    private func getOrCreateTodayEntry() -> DiaryEntry? {
        let now = Date()
        do {
            let entry = try DiaryEntryDailyStore.getOrCreateEntry(on: now, in: viewContext)
            try viewContext.save()
            return entry
        } catch {
            if let existing = todayDraftOrStartedEntry {
                return existing
            }
            let entry = DiaryEntry(context: viewContext)
            entry.id = UUID()
            entry.date = now
            entry.createdAt = now
            entry.text = ""
            entry.isStarred = false
            entry.updatedAt = now
            do {
                try viewContext.save()
                return entry
            } catch {
                viewContext.rollback()
                promptNoteError = String(localized: "Try again.")
                return nil
            }
        }
    }

    private func entryHasNoContent(_ entry: DiaryEntry) -> Bool {
        !entry.isStartedEntry
    }
}

// MARK: - Breathing orb

/// Slow, continuous "breathing" for Friday's aura. Off under Reduce Motion.
private struct FridayBreathingModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.phaseAnimator([false, true]) { view, isExhaling in
                view
                    .scaleEffect(isExhaling ? 1.04 : 0.97)
                    .opacity(isExhaling ? 1 : 0.82)
            } animation: { _ in
                .easeInOut(duration: 2.6)
            }
        }
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
