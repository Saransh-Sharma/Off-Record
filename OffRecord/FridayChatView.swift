//
//  FridayChatView.swift
//  OffRecord
//
//  Talk to Friday - a conversational interface to explore your journal data.
//  All responses are generated from on-device Friday data.
//  No external APIs or LLMs are used.
//

import SwiftUI
import CoreData
#if os(iOS)
import UIKit
#endif

// MARK: - Question Types

enum FridayQuestion: String, CaseIterable, Identifiable {
    case moodPattern = "What's my mood pattern this week?"
    case talkAboutMost = "Who do I talk about most?"
    case happiestWhen = "When am I happiest?"
    case dominantTopics = "What topics dominate my thoughts?"
    case moodOverTime = "How has my mood changed over time?"
    case communicationStyle = "What's my communication style?"
    case stressTriggers = "What triggers my stress?"
    case positiveOrNegative = "Am I more positive or negative overall?"
    case personality = "What's my personality like?"
    case bestJournalTime = "What time should I journal?"

    var id: String { rawValue }

    var accessibilityID: String {
        switch self {
        case .moodPattern: return "moodPattern"
        case .talkAboutMost: return "talkAboutMost"
        case .happiestWhen: return "happiestWhen"
        case .dominantTopics: return "dominantTopics"
        case .moodOverTime: return "moodOverTime"
        case .communicationStyle: return "communicationStyle"
        case .stressTriggers: return "stressTriggers"
        case .positiveOrNegative: return "positiveOrNegative"
        case .personality: return "personality"
        case .bestJournalTime: return "bestJournalTime"
        }
    }

    var icon: String {
        switch self {
        case .moodPattern: return "chart.line.uptrend.xyaxis"
        case .talkAboutMost: return "person.2.fill"
        case .happiestWhen: return "sun.max.fill"
        case .dominantTopics: return "tag.fill"
        case .moodOverTime: return "arrow.up.right"
        case .communicationStyle: return "text.bubble.fill"
        case .stressTriggers: return "bolt.heart.fill"
        case .positiveOrNegative: return "plusminus"
        case .personality: return "person.crop.circle.fill"
        case .bestJournalTime: return "clock.fill"
        }
    }
}

// MARK: - Chat Message

struct FridayChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp = Date()
    let evidence: [EvidenceReference]
    let observations: [EvidenceObservation]
    let confidence: Double?
    let limitations: String?

    init(text: String, isUser: Bool, evidence: [EvidenceReference] = [], observations: [EvidenceObservation] = [], confidence: Double? = nil, limitations: String? = nil) {
        self.text = text
        self.isUser = isUser
        self.evidence = evidence
        self.observations = observations
        self.confidence = confidence
        self.limitations = limitations
    }
}

// MARK: - Response Generator

@MainActor
struct FridayResponseGenerator {

    private static let insufficientData = FridayPersonality.insufficientData

    static func generateResponse(for question: FridayQuestion) -> String {
        let assistant = FridayAssistantEngine.shared
        let profile = LocalAIEngine.shared.userProfile
        let hasEnoughData = assistant.summary.dataPointsCollected >= 5

        switch question {
        case .moodPattern:
            return moodPatternResponse(assistant: assistant, hasData: hasEnoughData)
        case .talkAboutMost:
            return talkAboutMostResponse(assistant: assistant, hasData: hasEnoughData)
        case .happiestWhen:
            return happiestWhenResponse(assistant: assistant, hasData: hasEnoughData)
        case .dominantTopics:
            return dominantTopicsResponse(assistant: assistant, profile: profile, hasData: hasEnoughData)
        case .moodOverTime:
            return moodOverTimeResponse(assistant: assistant, hasData: hasEnoughData)
        case .communicationStyle:
            return communicationStyleResponse(assistant: assistant, hasData: hasEnoughData)
        case .stressTriggers:
            return stressTriggersResponse(assistant: assistant, hasData: hasEnoughData)
        case .positiveOrNegative:
            return positiveOrNegativeResponse(assistant: assistant, hasData: hasEnoughData)
        case .personality:
            return personalityResponse(assistant: assistant, hasData: hasEnoughData)
        case .bestJournalTime:
            return bestJournalTimeResponse(assistant: assistant, profile: profile, hasData: hasEnoughData)
        }
    }

    // MARK: - Individual Response Builders

    private static func moodPatternResponse(assistant: FridayAssistantEngine, hasData: Bool) -> String {
        guard hasData else { return insufficientData }

        let sig = assistant.emotionalSignature
        var parts: [String] = []

        // Recent sentiments
        if !sig.recentSentiments.isEmpty {
            let recent = Array(sig.recentSentiments.suffix(7))
            let avg = recent.reduce(0, +) / Double(recent.count)
            let moodWord: String
            if avg > 0.3 { moodWord = "quite positive" }
            else if avg > 0.1 { moodWord = "generally good" }
            else if avg > -0.1 { moodWord = "fairly balanced" }
            else if avg > -0.3 { moodWord = "a bit low" }
            else { moodWord = "on the tougher side" }
            parts.append("Your recent mood has been \(moodWord).")
        }

        // Weekday vs weekend
        let weekdayLabel = sentimentWord(sig.weekdayMood)
        let weekendLabel = sentimentWord(sig.weekendMood)
        if weekdayLabel != weekendLabel {
            parts.append("Weekdays feel \(weekdayLabel), while weekends are \(weekendLabel).")
        } else {
            parts.append("Your mood stays pretty consistent between weekdays and weekends.")
        }

        // Emotional range
        if sig.emotionalRange > 0.6 {
            parts.append("You experience a wide range of emotions - lots of highs and lows.")
        } else if sig.emotionalRange < 0.3 {
            parts.append("Your emotions tend to stay steady without big swings.")
        }

        return parts.isEmpty ? insufficientData : parts.joined(separator: " ")
    }

    private static func talkAboutMostResponse(assistant: FridayAssistantEngine, hasData: Bool) -> String {
        guard hasData else { return insufficientData }

        let people = assistant.knowledgeGraph.topNodes(ofType: .person, limit: 5)
        guard !people.isEmpty else {
            return "I haven't picked up on specific people in your entries yet. Try mentioning people by name and I'll start tracking who matters most to you."
        }

        var parts: [String] = []
        let top = people[0]
        parts.append("\(top.label) comes up the most in your journal (\(top.mentions) mentions).")

        if top.sentimentAssociation > 0.2 {
            parts.append("You tend to feel positive when writing about them.")
        } else if top.sentimentAssociation < -0.2 {
            parts.append("Entries about them carry some heavier emotions.")
        }

        if people.count > 1 {
            let others = people.dropFirst().prefix(3).map { $0.label }
            parts.append("You also mention \(others.joined(separator: ", ")) frequently.")
        }

        return parts.joined(separator: " ")
    }

    private static func happiestWhenResponse(assistant: FridayAssistantEngine, hasData: Bool) -> String {
        guard hasData else { return insufficientData }

        let sig = assistant.emotionalSignature
        var parts: [String] = []

        // Time of day
        let morningBetter = sig.morningMood > sig.eveningMood
        if abs(sig.morningMood - sig.eveningMood) > 0.1 {
            parts.append("You tend to be happier in the \(morningBetter ? "morning" : "evening").")
        } else {
            parts.append("Your mood is fairly consistent throughout the day.")
        }

        // Weekday vs weekend
        if sig.weekendMood > sig.weekdayMood + 0.1 {
            parts.append("Weekends clearly lift your spirits.")
        } else if sig.weekdayMood > sig.weekendMood + 0.1 {
            parts.append("Interestingly, you seem happier on weekdays.")
        }

        // Positive triggers
        let positiveTriggers = sig.positiveTriggersTopics
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key.capitalized }

        if !positiveTriggers.isEmpty {
            parts.append("Topics that lift your mood include: \(positiveTriggers.joined(separator: ", ")).")
        }

        return parts.isEmpty ? insufficientData : parts.joined(separator: " ")
    }

    private static func dominantTopicsResponse(assistant: FridayAssistantEngine, profile: UserProfile, hasData: Bool) -> String {
        guard hasData else { return insufficientData }

        let graphTopics = assistant.knowledgeGraph.topNodes(ofType: .topic, limit: 5)
        let profileTopics = profile.commonTopics.sorted { $0.value > $1.value }.prefix(5)

        var allTopics: [String] = []
        for node in graphTopics {
            allTopics.append(node.label)
        }
        for (topic, _) in profileTopics {
            let capitalized = topic.capitalized
            if !allTopics.contains(where: { $0.lowercased() == capitalized.lowercased() }) {
                allTopics.append(capitalized)
            }
        }

        guard !allTopics.isEmpty else {
            return "I haven't identified strong themes yet. The more you journal, the clearer your thought patterns will become."
        }

        let topList = allTopics.prefix(5).joined(separator: ", ")
        var response = "The themes that dominate your journal are: \(topList)."

        // Add concerns if available
        let concerns = assistant.thoughtPatterns.topConcerns
            .sorted { $0.value > $1.value }
            .prefix(2)
            .map { $0.key.capitalized }
        if !concerns.isEmpty {
            response += " Your main concerns seem to revolve around \(concerns.joined(separator: " and "))."
        }

        return response
    }

    private static func moodOverTimeResponse(assistant: FridayAssistantEngine, hasData: Bool) -> String {
        guard hasData else { return insufficientData }

        let sig = assistant.emotionalSignature
        var parts: [String] = []

        // Trend
        if sig.sentimentTrend > 0.05 {
            parts.append("Your mood has been trending upward recently. Things are looking brighter.")
        } else if sig.sentimentTrend < -0.05 {
            parts.append("Your mood has been dipping a bit lately. That's okay - acknowledging it is the first step.")
        } else {
            parts.append("Your emotional state has been fairly stable recently.")
        }

        // Baseline
        let baselineWord: String
        if sig.baselineValence > 0.2 { baselineWord = "positive" }
        else if sig.baselineValence > -0.1 { baselineWord = "balanced" }
        else { baselineWord = "reflective" }
        parts.append("Your overall emotional baseline is \(baselineWord).")

        // Resilience
        if sig.resilienceScore > 0.6 {
            parts.append("You show good emotional resilience - you bounce back well.")
        }

        // Data points
        if sig.recentSentiments.count >= 10 {
            parts.append("This is based on your last \(sig.recentSentiments.count) journal entries.")
        }

        return parts.joined(separator: " ")
    }

    private static func communicationStyleResponse(assistant: FridayAssistantEngine, hasData: Bool) -> String {
        guard hasData, assistant.communicationStyle.analysisCount >= 3 else { return insufficientData }

        let style = assistant.communicationStyle
        var parts: [String] = []

        // Formality
        if style.formalityLevel > 0.6 {
            parts.append("You write in a fairly formal, polished way.")
        } else if style.formalityLevel < 0.4 {
            parts.append("Your writing style is casual and conversational.")
        } else {
            parts.append("Your writing strikes a nice balance between casual and formal.")
        }

        // Expressiveness
        if style.expressiveness > 0.6 {
            parts.append("You're quite expressive - you use exclamations and vivid language.")
        } else if style.expressiveness < 0.3 {
            parts.append("You tend to be measured and understated in your expression.")
        }

        // Directness
        if style.directness > 0.6 {
            parts.append("You're direct and to the point.")
        } else if style.directness < 0.4 {
            parts.append("You often take a more nuanced, reflective approach.")
        }

        // Sentence length
        parts.append("Your average sentence is about \(Int(style.averageSentenceLength)) words long.")

        // Signature words
        let topWords = style.signatureWords
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
        if !topWords.isEmpty {
            parts.append("Some of your signature words are: \(topWords.joined(separator: ", ")).")
        }

        return parts.joined(separator: " ")
    }

    private static func stressTriggersResponse(assistant: FridayAssistantEngine, hasData: Bool) -> String {
        guard hasData else { return insufficientData }

        let negativeTriggers = assistant.emotionalSignature.negativeTriggersTopics
            .sorted { $0.value > $1.value }
            .prefix(5)

        guard !negativeTriggers.isEmpty else {
            return "I haven't identified clear stress triggers yet. This is actually a good sign! As you journal more, I'll be able to spot patterns in what weighs on you."
        }

        let triggerList = negativeTriggers.map { $0.key.capitalized }
        var response = "Based on your entries, these topics tend to bring your mood down: \(triggerList.joined(separator: ", "))."

        // Contrast with positive
        let positiveTriggers = assistant.emotionalSignature.positiveTriggersTopics
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key.capitalized }
        if !positiveTriggers.isEmpty {
            response += " On the flip side, \(positiveTriggers.joined(separator: ", ")) tend to lift you up."
        }

        return response
    }

    private static func positiveOrNegativeResponse(assistant: FridayAssistantEngine, hasData: Bool) -> String {
        guard hasData else { return insufficientData }

        let valence = assistant.emotionalSignature.baselineValence
        var parts: [String] = []

        if valence > 0.2 {
            parts.append("Overall, your journal entries lean positive. You tend to focus on good things.")
        } else if valence > 0.05 {
            parts.append("You're slightly on the positive side - a healthy, realistic optimism.")
        } else if valence > -0.05 {
            parts.append("You're remarkably balanced. Your entries show an even mix of positive and negative.")
        } else if valence > -0.2 {
            parts.append("Your entries lean slightly toward processing challenges. That's what journaling is great for.")
        } else {
            parts.append("You've been working through some tough things. Your journal is a safe space for that.")
        }

        // Emotion frequency breakdown
        let emotions = assistant.emotionalSignature.emotionFrequency
            .sorted { $0.value > $1.value }
            .prefix(3)
        if !emotions.isEmpty {
            let topEmotions = emotions.map { "\($0.key.capitalized)" }
            parts.append("Your most frequent moods are: \(topEmotions.joined(separator: ", ")).")
        }

        return parts.joined(separator: " ")
    }

    private static func personalityResponse(assistant: FridayAssistantEngine, hasData: Bool) -> String {
        guard hasData else { return insufficientData }

        let fridayProfile = FridayProfileGenerator.generate()
        var parts: [String] = []

        parts.append("Here's what your journal reveals about you:")

        // Core traits from profile
        let traitDescriptions = fridayProfile.traits.map { $0.displayLabel }
        if !traitDescriptions.isEmpty {
            parts.append("Your core traits are: \(traitDescriptions.joined(separator: ", ")).")
        }

        // Communication & thinking style
        parts.append("Communication style: \(fridayProfile.communicationStyle). Thinking style: \(fridayProfile.thinkingStyle).")

        // Dominant mood
        parts.append("Your dominant mood is \(fridayProfile.dominantMood) with \(fridayProfile.emotionalRange.lowercased()) emotional range.")

        // Growth indicators
        if assistant.thoughtPatterns.growthMindsetScore > 0.6 {
            parts.append("You show a strong growth mindset.")
        }
        if assistant.thoughtPatterns.gratitudeTendency > 0.5 {
            parts.append("Gratitude is a natural part of how you think.")
        }
        if assistant.thoughtPatterns.selfAwarenessLevel > 0.6 {
            parts.append("You have a high level of self-awareness.")
        }

        return parts.joined(separator: " ")
    }

    private static func bestJournalTimeResponse(assistant: FridayAssistantEngine, profile: UserProfile, hasData: Bool) -> String {
        guard hasData else { return insufficientData }

        var parts: [String] = []

        // Peak hour from behavioral patterns
        if let peakHour = assistant.behavioralPatterns.peakHour {
            parts.append("Based on your habits, you journal most often around \(formatHour(peakHour)).")
        }

        // Cross-reference with mood
        let sig = assistant.emotionalSignature
        if sig.morningMood > sig.eveningMood + 0.1 {
            parts.append("You tend to be in a better mood in the morning, so that might be ideal for reflection.")
        } else if sig.eveningMood > sig.morningMood + 0.1 {
            parts.append("Your evening entries tend to be more positive - evenings might be your sweet spot.")
        }

        // Peak day
        if let peakDay = assistant.behavioralPatterns.peakDay {
            let days = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            if peakDay >= 1 && peakDay <= 7 {
                parts.append("\(days[peakDay]) is when you journal most frequently.")
            }
        }

        // Consistency note
        if assistant.behavioralPatterns.consistencyScore > 0.5 {
            parts.append("You've built a solid journaling habit - keep it up!")
        } else {
            parts.append("Try picking a consistent time each day to build the habit.")
        }

        return parts.isEmpty ? insufficientData : parts.joined(separator: " ")
    }

    // MARK: - Helpers

    private static func sentimentWord(_ value: Double) -> String {
        if value > 0.3 { return "great" }
        if value > 0.1 { return "good" }
        if value > -0.1 { return "neutral" }
        if value > -0.3 { return "a bit low" }
        return "tough"
    }

    private static func formatHour(_ hour: Int) -> String {
        if hour == 0 { return "midnight" }
        if hour < 12 { return "\(hour)am" }
        if hour == 12 { return "noon" }
        return "\(hour - 12)pm"
    }
}

// MARK: - Friday Chat View

enum FridayChatLayout {
    static let compactBackButtonTopPadding: CGFloat = 32
    static let regularBackButtonTopPadding: CGFloat = 24
    static let compactComposerBottomClearance: CGFloat = 52
    static let regularComposerBottomClearance: CGFloat = 16
    static let minimumTapTarget: CGFloat = 44

    static func backButtonTopPadding(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        horizontalSizeClass == .compact ? compactBackButtonTopPadding : regularBackButtonTopPadding
    }

    static func composerBottomClearance(
        horizontalSizeClass: UserInterfaceSizeClass?,
        isKeyboardVisible: Bool
    ) -> CGFloat {
        guard horizontalSizeClass == .compact else {
            return regularComposerBottomClearance
        }

        guard isKeyboardVisible else {
            return compactComposerBottomClearance
        }

        return OffRecordCompactTabBarLayout.composerKeyboardVisibleClearance
    }
}

struct FridayChatView: View {
    private let initialQuestion: String?
    private let autoSubmitInitialQuestion: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var semanticMemory = SemanticMemoryIndexController.shared
    @AppStorage("authorName") private var authorName: String = ""

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)],
        animation: .default)
    private var entries: FetchedResults<DiaryEntry>

    @State private var messages: [FridayChatMessage] = []
    @State private var askedQuestions: Set<FridayQuestion> = []
    @State private var inputText: String = ""
    @State private var isAnswering = false
    @State private var appliedInitialQuestion = false
    @State private var isKeyboardVisible = false

    private var startedEntries: [DiaryEntry] { entries.startedEntries }

    init(initialQuestion: String? = nil, autoSubmitInitialQuestion: Bool = false) {
        self.initialQuestion = initialQuestion
        self.autoSubmitInitialQuestion = autoSubmitInitialQuestion
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = OffRecordAdaptiveMetrics(
                width: geometry.size.width,
                horizontalSizeClass: horizontalSizeClass
            )

            ScrollViewReader { proxy in
                ZStack(alignment: .topLeading) {
                    FridayChatBackground()

                    ScrollView {
                        VStack(spacing: contentSpacing) {
                            screenContent

                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, topContentPadding)
                        .padding(.bottom, scrollBottomPadding)
                        .frame(maxWidth: metrics.fridayReadableWidth)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                    .accessibilityIdentifier("friday.questionChips")

                    FridayBackButton {
                        dismiss()
                    }
                    .padding(.leading, OffRecordSpacing.xxl)
                    .padding(.top, backButtonTopPadding)
                }
                .safeAreaInset(edge: .bottom) {
                    FridayComposer(
                        text: $inputText,
                        isAnswering: isAnswering,
                        isIndexing: semanticMemory.isBuilding,
                        indexingProgress: semanticMemory.progress,
                        indexingMessage: semanticMemory.statusMessage,
                        maxWidth: metrics.fridayReadableWidth,
                        onSend: askFreeformQuestion
                    )
                    .padding(.bottom, composerBottomClearance)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.28)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: isAnswering) { _, _ in
                    withAnimation(.easeOut(duration: 0.28)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .background(OffRecordColor.appBackgroundGradient.ignoresSafeArea())
        .task {
            semanticMemory.ensureIndexed(entries: startedEntries)
            applyInitialQuestionIfNeeded()
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        #endif
    }

    @ViewBuilder
    private var screenContent: some View {
        switch screenMode {
        case .activeChat:
            FridayActiveChatHeader()
            FridayMessageList(
                messages: messages,
                isAnswering: isAnswering,
                entryProvider: entry(for:)
            )
            FridayPromptSection(
                title: "Or ask me something",
                questions: compactQuestions,
                askedQuestions: askedQuestions,
                layout: .grid,
                action: askQuestion
            )
        case .loadingIndex:
            FridayWarmMinimalContent(
                userName: authorName,
                questions: landingQuestions,
                askedQuestions: askedQuestions,
                mode: .indexing(semanticMemory.statusMessage),
                action: askQuestion
            )
        case .noJournalData:
            FridayWarmMinimalContent(
                userName: authorName,
                questions: noDataQuestions,
                askedQuestions: askedQuestions,
                mode: .noJournalData,
                action: askQuestion
            )
        case .warmMinimal, .error:
            FridayWarmMinimalContent(
                userName: authorName,
                questions: landingQuestions,
                askedQuestions: askedQuestions,
                mode: .warm,
                action: askQuestion
            )
        }
    }

    private var screenMode: FridayChatScreenMode {
        if !messages.isEmpty || isAnswering {
            return .activeChat
        }
        if startedEntries.count < 5 {
            return .noJournalData
        }
        if semanticMemory.isBuilding {
            return .loadingIndex
        }
        return .warmMinimal
    }

    private var landingQuestions: [FridayQuestion] {
        [.moodPattern, .stressTriggers, .talkAboutMost, .dominantTopics]
    }

    private var compactQuestions: [FridayQuestion] {
        [.moodPattern, .stressTriggers, .talkAboutMost, .happiestWhen]
    }

    private var noDataQuestions: [FridayQuestion] {
        [.bestJournalTime, .communicationStyle, .moodPattern, .dominantTopics]
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .compact ? OffRecordSpacing.xxl : 40
    }

    private var topContentPadding: CGFloat {
        if screenMode == .activeChat {
            return horizontalSizeClass == .compact ? 82 : 72
        }
        return horizontalSizeClass == .compact ? 48 : 64
    }

    private var contentSpacing: CGFloat {
        screenMode == .activeChat ? 18 : 0
    }

    private var composerBottomClearance: CGFloat {
        FridayChatLayout.composerBottomClearance(
            horizontalSizeClass: horizontalSizeClass,
            isKeyboardVisible: isKeyboardVisible
        )
    }

    private var backButtonTopPadding: CGFloat {
        FridayChatLayout.backButtonTopPadding(horizontalSizeClass: horizontalSizeClass)
    }

    private var scrollBottomPadding: CGFloat {
        horizontalSizeClass == .compact ? 260 : 160
    }

    private func applyInitialQuestionIfNeeded() {
        guard !appliedInitialQuestion else { return }
        appliedInitialQuestion = true
        let question = initialQuestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !question.isEmpty else { return }
        if autoSubmitInitialQuestion {
            askEvidenceQuestion(question, profileSummary: nil)
        } else if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputText = question
        }
    }

    private func askQuestion(_ question: FridayQuestion) {
        askEvidenceQuestion(question.rawValue, profileSummary: FridayResponseGenerator.generateResponse(for: question))
        askedQuestions.insert(question)
    }

    private var canSendFreeform: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAnswering && !semanticMemory.isBuilding
    }

    private func askFreeformQuestion() {
        let question = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSendFreeform else { return }
        inputText = ""
        askEvidenceQuestion(question, profileSummary: nil)
    }

    private func askEvidenceQuestion(_ question: String, profileSummary: String?) {
        guard !isAnswering else { return }
        // Add user message
        let userMessage = FridayChatMessage(text: question, isUser: true)
        messages.append(userMessage)
        isAnswering = true
        let entrySnapshot = startedEntries

        Task {
            let answer = await EvidenceFridayEngine.answer(question: question, entries: entrySnapshot, profileSummary: profileSummary)
            let text = ([answer.summary] + answer.observations.map(\.text)).joined(separator: " ")
            let fridayMessage = FridayChatMessage(
                text: text,
                isUser: false,
                evidence: answer.evidence,
                observations: answer.observations,
                confidence: answer.confidence,
                limitations: answer.limitations
            )
            withAnimation(.easeIn(duration: 0.2)) {
                messages.append(fridayMessage)
                isAnswering = false
            }
        }
    }

    private func entry(for id: UUID) -> DiaryEntry? {
        startedEntries.first { $0.id == id }
    }
}

#Preview {
    NavigationStack {
        FridayChatView()
    }
}
