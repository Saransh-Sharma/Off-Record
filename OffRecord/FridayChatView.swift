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

/// Suggested questions. The rawValue is a stable ID: chat history persists it, and it
/// doubles as the search query. `question` is what the pill shows and the chat sends.
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

    /// The pill label, and the text sent as the user's message.
    var question: String {
        switch self {
        case .moodPattern: return String(localized: "How’s my mood this week?")
        case .talkAboutMost: return String(localized: "Who do I mention most?")
        case .happiestWhen: return String(localized: "When am I happiest?")
        case .dominantTopics: return String(localized: "What keeps coming up?")
        case .moodOverTime: return String(localized: "How has my mood changed?")
        case .communicationStyle: return String(localized: "How do I write?")
        case .stressTriggers: return String(localized: "What’s been stressing me?")
        case .positiveOrNegative: return String(localized: "What’s my overall tone?")
        case .personality: return String(localized: "What’s my personality like?")
        case .bestJournalTime: return String(localized: "When do I journal most?")
        }
    }

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

struct FridayChatMessage: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    /// The question for user messages; the lead summary for Friday's answers.
    let summary: String
    let isUser: Bool
    let evidence: [EvidenceReference]
    let observations: [EvidenceObservation]
    let confidence: Double?
    let limitations: String?
    let followUps: [FridayFollowUp]

    /// A user message.
    init(id: UUID = UUID(), timestamp: Date = Date(), text: String, isUser: Bool) {
        self.init(id: id, timestamp: timestamp, summary: text, isUser: isUser)
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        summary: String,
        isUser: Bool,
        evidence: [EvidenceReference] = [],
        observations: [EvidenceObservation] = [],
        confidence: Double? = nil,
        limitations: String? = nil,
        followUps: [FridayFollowUp] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.summary = summary
        self.isUser = isUser
        self.evidence = evidence
        self.observations = observations
        self.confidence = confidence
        self.limitations = limitations
        self.followUps = followUps
    }

    var segments: [FridayAnswerSegment] {
        guard !isUser else { return [FridayAnswerSegment(text: summary, citations: [])] }
        return FridayAnswerComposer.segments(summary: summary, observations: observations, evidence: evidence)
    }

    /// The message as plain text, without citation markers (for copy, share, and VoiceOver).
    var text: String {
        FridayAnswerComposer.plainText(segments)
    }

    var evidenceStrength: FridayEvidenceStrength? {
        isUser ? nil : FridayEvidenceStrength.assess(confidence: confidence, evidence: evidence)
    }
}

/// A cited entry opened from an evidence chip; `sourceID` drives the zoom transition.
struct FridayEvidenceSelection: Hashable {
    let entry: DiaryEntry
    let sourceID: String
}

struct FridayChatError: Equatable {
    /// The question to retry, or nil when the journal index itself failed.
    let question: String?
    let profileSummary: String?
    let detail: String
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
            if avg > 0.3 { moodWord = String(localized: "mostly good", comment: "Fills “Your recent mood has been …”") }
            else if avg > 0.1 { moodWord = String(localized: "good", comment: "Fills “Your recent mood has been …”") }
            else if avg > -0.1 { moodWord = String(localized: "mixed", comment: "Fills “Your recent mood has been …”") }
            else if avg > -0.3 { moodWord = String(localized: "a bit low", comment: "Fills “Your recent mood has been …”") }
            else { moodWord = String(localized: "hard", comment: "Fills “Your recent mood has been …”") }
            parts.append(String(localized: "Your recent mood has been \(moodWord)."))
        }

        // Weekday vs weekend
        let weekdayLabel = sentimentWord(sig.weekdayMood)
        let weekendLabel = sentimentWord(sig.weekendMood)
        if weekdayLabel != weekendLabel {
            parts.append(String(localized: "Weekdays feel \(weekdayLabel). Weekends feel \(weekendLabel)."))
        } else {
            parts.append(String(localized: "Weekdays and weekends feel about the same."))
        }

        // Emotional range
        if let range = rangeSentence(sig.emotionalRange) {
            parts.append(range)
        }

        return parts.isEmpty ? insufficientData : parts.joined(separator: " ")
    }

    private static func talkAboutMostResponse(assistant: FridayAssistantEngine, hasData: Bool) -> String {
        guard hasData else { return insufficientData }

        let people = assistant.knowledgeGraph.fridayVisibleNodes(ofType: .person, limit: 5)
        guard !people.isEmpty else {
            return String(localized: "I haven’t seen anyone by name yet. Mention people by name and I’ll keep track.")
        }

        var parts: [String] = []
        let top = people[0]
        let times = String(AttributedString(localized: "^[\(top.mentions) time](inflect: true)").characters)
        parts.append(String(localized: "You mention \(top.label) most, \(times) so far."))

        if top.sentimentAssociation > 0.2 {
            parts.append(String(localized: "Those entries are usually upbeat."))
        } else if top.sentimentAssociation < -0.2 {
            parts.append(String(localized: "Those entries tend to be heavier."))
        }

        if people.count > 1 {
            let others = people.dropFirst().prefix(3).map { $0.label }
            parts.append(String(localized: "You also mention \(list(others)) often."))
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
            parts.append(morningBetter
                ? String(localized: "You’re happier in the morning.")
                : String(localized: "You’re happier in the evening."))
        } else {
            parts.append(String(localized: "Your mood stays about the same through the day."))
        }

        // Weekday vs weekend
        if sig.weekendMood > sig.weekdayMood + 0.1 {
            parts.append(String(localized: "You’re happier on weekends."))
        } else if sig.weekdayMood > sig.weekendMood + 0.1 {
            parts.append(String(localized: "You’re happier on weekdays."))
        }

        // Positive triggers
        let positiveTriggers = sig.positiveTriggersTopics
            .filter { !FridayMemoryPreferences.shared.isForgottenLabel($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key.capitalized }

        if !positiveTriggers.isEmpty {
            parts.append(String(localized: "Your mood lifts when you write about \(list(positiveTriggers))."))
        }

        return parts.isEmpty ? insufficientData : parts.joined(separator: " ")
    }

    private static func dominantTopicsResponse(assistant: FridayAssistantEngine, profile: UserProfile, hasData: Bool) -> String {
        guard hasData else { return insufficientData }

        let graphTopics = assistant.knowledgeGraph.fridayVisibleNodes(ofType: .topic, limit: 5)
        let profileTopics = profile.commonTopics
            .filter { !FridayMemoryPreferences.shared.isForgottenLabel($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(5)

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
            return String(localized: "No clear topics yet. I’ll see more after a few entries.")
        }

        var response = String(localized: "You write most about \(list(Array(allTopics.prefix(5)))).")

        // Add concerns if available
        let concerns = assistant.thoughtPatterns.topConcerns
            .filter { !FridayMemoryPreferences.shared.isForgottenLabel($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(2)
            .map { $0.key.capitalized }
        if concerns.count == 1 {
            response += " " + String(localized: "Your biggest worry is \(concerns[0]).")
        } else if !concerns.isEmpty {
            response += " " + String(localized: "Your biggest worries are \(list(concerns)).")
        }

        return response
    }

    private static func moodOverTimeResponse(assistant: FridayAssistantEngine, hasData: Bool) -> String {
        guard hasData else { return insufficientData }

        let sig = assistant.emotionalSignature
        var parts: [String] = []

        // Trend
        if sig.sentimentTrend > 0.05 {
            parts.append(String(localized: "Your mood has been improving lately."))
        } else if sig.sentimentTrend < -0.05 {
            parts.append(String(localized: "Your mood has dipped a bit lately."))
        } else {
            parts.append(String(localized: "Your mood has been steady lately."))
        }

        // Overall lean
        if sig.baselineValence > 0.2 {
            parts.append(String(localized: "Overall, it leans positive."))
        } else if sig.baselineValence > -0.1 {
            parts.append(String(localized: "Overall, it’s fairly even."))
        } else {
            parts.append(String(localized: "Overall, it leans low."))
        }

        // Resilience
        if sig.resilienceScore > 0.6 {
            parts.append(String(localized: "After hard days, you tend to bounce back quickly."))
        }

        // Data points
        if sig.recentSentiments.count >= 10 {
            parts.append(String(localized: "Based on your last \(sig.recentSentiments.count) entries."))
        }

        return parts.joined(separator: " ")
    }

    private static func communicationStyleResponse(assistant: FridayAssistantEngine, hasData: Bool) -> String {
        guard hasData, assistant.communicationStyle.analysisCount >= 3 else { return insufficientData }

        let style = assistant.communicationStyle
        var parts: [String] = []

        // Formality
        if style.formalityLevel > 0.6 {
            parts.append(String(localized: "You write formally."))
        } else if style.formalityLevel < 0.4 {
            parts.append(String(localized: "You write the way you talk."))
        } else {
            parts.append(String(localized: "You write somewhere between casual and formal."))
        }

        // Expressiveness
        if style.expressiveness > 0.6 {
            parts.append(String(localized: "You write with a lot of feeling."))
        } else if style.expressiveness < 0.3 {
            parts.append(String(localized: "You keep your feelings understated."))
        }

        // Directness
        if style.directness > 0.6 {
            parts.append(String(localized: "You get to the point."))
        } else if style.directness < 0.4 {
            parts.append(String(localized: "You think things through on the page."))
        }

        // Sentence length
        parts.append(String(localized: "Your sentences average \(Int(style.averageSentenceLength)) words."))

        // Signature words
        let topWords = style.signatureWords
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
        if !topWords.isEmpty {
            parts.append(String(localized: "Words you use often: \(list(topWords))."))
        }

        return parts.joined(separator: " ")
    }

    private static func stressTriggersResponse(assistant: FridayAssistantEngine, hasData: Bool) -> String {
        guard hasData else { return insufficientData }

        let negativeTriggers = assistant.emotionalSignature.negativeTriggersTopics
            .filter { !FridayMemoryPreferences.shared.isForgottenLabel($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(5)

        guard !negativeTriggers.isEmpty else {
            return String(localized: "Nothing stands out as a stressor yet.")
        }

        let triggerList = negativeTriggers.map { $0.key.capitalized }
        var response = String(localized: "Your mood tends to drop when you write about \(list(triggerList)).")

        // Contrast with positive
        let positiveTriggers = assistant.emotionalSignature.positiveTriggersTopics
            .filter { !FridayMemoryPreferences.shared.isForgottenLabel($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key.capitalized }
        if !positiveTriggers.isEmpty {
            let lifters = list(positiveTriggers)
            response += " " + (positiveTriggers.count == 1
                ? String(localized: "\(lifters) tends to lift it.", comment: "The placeholder is one topic")
                : String(localized: "\(lifters) tend to lift it.", comment: "The placeholder is a list of topics"))
        }

        return response
    }

    private static func positiveOrNegativeResponse(assistant: FridayAssistantEngine, hasData: Bool) -> String {
        guard hasData else { return insufficientData }

        let valence = assistant.emotionalSignature.baselineValence
        var parts: [String] = []

        if valence > 0.2 {
            parts.append(String(localized: "Your entries lean positive."))
        } else if valence > 0.05 {
            parts.append(String(localized: "Your entries lean slightly positive."))
        } else if valence > -0.05 {
            parts.append(String(localized: "Your entries are an even mix of good and hard days."))
        } else if valence > -0.2 {
            parts.append(String(localized: "Your entries lean slightly toward hard days."))
        } else {
            parts.append(String(localized: "You’ve been writing through some hard things lately."))
        }

        // Emotion frequency breakdown
        let emotions = assistant.emotionalSignature.emotionFrequency
            .sorted { $0.value > $1.value }
            .prefix(3)
        if !emotions.isEmpty {
            let topEmotions = emotions.map { $0.key.lowercased() }
            if topEmotions.count == 1 {
                parts.append(String(localized: "Your most common mood is \(topEmotions[0])."))
            } else {
                parts.append(String(localized: "Your most common moods are \(list(topEmotions))."))
            }
        }

        return parts.joined(separator: " ")
    }

    private static func personalityResponse(assistant: FridayAssistantEngine, hasData: Bool) -> String {
        guard hasData else { return insufficientData }

        let fridayProfile = FridayProfileGenerator.generate()
        var parts: [String] = []

        // Core traits from profile
        var traitWords: [String] = []
        for trait in fridayProfile.traits.map({ $0.displayLabel.lowercased() }) where !traitWords.contains(trait) {
            traitWords.append(trait)
        }
        if !traitWords.isEmpty {
            parts.append(String(localized: "You come across as \(list(traitWords))."))
        }

        // Writing and thinking style
        parts.append(String(localized: "Writing style: \(fridayProfile.communicationStyle). Thinking style: \(fridayProfile.thinkingStyle)."))

        // Usual mood and range
        parts.append(String(localized: "Your usual mood is \(fridayProfile.dominantMood.lowercased())."))
        if let range = rangeSentence(assistant.emotionalSignature.emotionalRange) {
            parts.append(range)
        }

        // Growth indicators
        if assistant.thoughtPatterns.growthMindsetScore > 0.6 {
            parts.append(String(localized: "You write a lot about learning and improving."))
        }
        if assistant.thoughtPatterns.gratitudeTendency > 0.5 {
            parts.append(String(localized: "You often write about what you’re grateful for."))
        }
        if assistant.thoughtPatterns.selfAwarenessLevel > 0.6 {
            parts.append(String(localized: "You notice a lot about yourself."))
        }

        return parts.joined(separator: " ")
    }

    private static func bestJournalTimeResponse(assistant: FridayAssistantEngine, profile: UserProfile, hasData: Bool) -> String {
        guard hasData else { return insufficientData }

        var parts: [String] = []

        // Peak hour from behavioral patterns
        if let peakHour = assistant.behavioralPatterns.peakHour {
            parts.append(String(localized: "You journal most around \(formatHour(peakHour)).", comment: "The placeholder is an hour of the day, like “9 PM”"))
        }

        // Cross-reference with mood
        let sig = assistant.emotionalSignature
        if sig.morningMood > sig.eveningMood + 0.1 {
            parts.append(String(localized: "Your morning entries are more upbeat."))
        } else if sig.eveningMood > sig.morningMood + 0.1 {
            parts.append(String(localized: "Your evening entries are more upbeat."))
        }

        // Peak day
        if let peakDay = assistant.behavioralPatterns.peakDay {
            let days = Calendar.current.weekdaySymbols
            if peakDay >= 1 && peakDay <= days.count {
                let day = days[peakDay - 1]
                parts.append(String(localized: "\(day) is when you journal most.", comment: "The placeholder is a weekday name, e.g. Sunday"))
            }
        }

        // Consistency note
        if assistant.behavioralPatterns.consistencyScore > 0.5 {
            parts.append(String(localized: "You journal regularly."))
        } else {
            parts.append(String(localized: "A set time each day can make it easier."))
        }

        return parts.isEmpty ? insufficientData : parts.joined(separator: " ")
    }

    // MARK: - Helpers

    private static func sentimentWord(_ value: Double) -> String {
        if value > 0.3 { return String(localized: "great", comment: "Fills “Weekdays feel … Weekends feel …”") }
        if value > 0.1 { return String(localized: "good", comment: "Fills “Weekdays feel … Weekends feel …”") }
        if value > -0.1 { return String(localized: "okay", comment: "Fills “Weekdays feel … Weekends feel …”") }
        if value > -0.3 { return String(localized: "a bit low", comment: "Fills “Weekdays feel … Weekends feel …”") }
        return String(localized: "hard", comment: "Fills “Weekdays feel … Weekends feel …”")
    }

    /// One sentence about how much moods swing, or nil for the middle of the range.
    private static func rangeSentence(_ range: Double) -> String? {
        if range > 0.6 { return String(localized: "Your moods swing quite a bit.") }
        if range < 0.3 { return String(localized: "Your moods stay fairly steady.") }
        return nil
    }

    /// "A, B, and C", localized.
    private static func list(_ items: [String]) -> String {
        ListFormatter.localizedString(byJoining: items)
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

// MARK: - Friday Chat View

enum FridayChatLayout {
    static let compactBackButtonTopPadding: CGFloat = 32
    static let regularBackButtonTopPadding: CGFloat = 24
    static let compactComposerBottomClearance: CGFloat = 8
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

        // The tab bar is hidden in chat, so the composer only needs a small gap
        // above the home indicator or keyboard.
        return isKeyboardVisible ? 0 : compactComposerBottomClearance
    }
}

struct FridayChatView: View {
    private let initialQuestion: String?
    private let autoSubmitInitialQuestion: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var semanticMemory = SemanticMemoryIndexController.shared
    @ObservedObject private var assistant = FridayAssistantEngine.shared
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
    /// How far the keyboard reaches up from the bottom of the screen.
    @State private var keyboardHeight: CGFloat = 0
    @State private var screenHeight: CGFloat = 0
    @State private var hasRestoredHistory = false
    @State private var revealingMessageID: UUID?
    @State private var chatError: FridayChatError?
    @State private var indexErrorDismissed = false
    @State private var selectedEvidence: FridayEvidenceSelection?
    @State private var isConfirmingNewChat = false
    @State private var answerFeedbackTrigger = 0
    @State private var newChatTrigger = 0
    @Namespace private var evidenceNamespace

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
            let contentWidth = max(0, min(geometry.size.width, metrics.fridayReadableWidth) - horizontalPadding * 2)

            ScrollViewReader { proxy in
                ZStack(alignment: .topLeading) {
                    FridayChatBackground()

                    ScrollView {
                        VStack(spacing: contentSpacing) {
                            screenContent(contentWidth: contentWidth)

                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, topContentPadding)
                        .padding(.bottom, scrollBottomPadding + keyboardLift(containerBottom: geometry.frame(in: .global).maxY))
                        .frame(maxWidth: metrics.fridayReadableWidth)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .accessibilityIdentifier("friday.questionChips")

                    FridayBackButton {
                        dismiss()
                    }
                    .padding(.leading, OffRecordSpacing.xxl)
                    .padding(.top, backButtonTopPadding)
                }
                .overlay(alignment: .bottom) {
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
                    // Cover the clearance too, so chat content doesn't show through below the composer.
                    .background(OffRecordColor.backgroundPrimary.opacity(0.98).ignoresSafeArea())
                    // Automatic keyboard avoidance doesn't reliably reach this screen inside the tab
                    // view, so the composer is lifted by exactly the part of it the keyboard covers.
                    .offset(y: -keyboardLift(containerBottom: geometry.frame(in: .global).maxY))
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: isAnswering) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: revealingMessageID) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: chatError) { _, _ in
                    scrollToBottom(proxy)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        // Inside the tab view with the tab bar hidden, automatic keyboard avoidance doesn't
        // reliably lift the composer, so the chat lifts it itself from the keyboard frame.
        .ignoresSafeArea(.keyboard)
        .onAppear { OffRecordNavigationRouter.shared.hidesCaptureAccessory = true }
        .onDisappear { OffRecordNavigationRouter.shared.hidesCaptureAccessory = false }
        .background(OffRecordAppBackground().ignoresSafeArea())
        .navigationDestination(item: $selectedEvidence) { selection in
            EntryDetailView(entry: selection.entry)
                .navigationTransition(.zoom(sourceID: selection.sourceID, in: evidenceNamespace))
        }
        .confirmationDialog(
            "Start a New Chat?",
            isPresented: $isConfirmingNewChat,
            titleVisibility: .visible
        ) {
            Button("New Chat", role: .destructive, action: startNewChat)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This conversation will be cleared. Your journal won’t change.")
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: answerFeedbackTrigger)
        .sensoryFeedback(.success, trigger: newChatTrigger)
        .task {
            restoreHistoryIfNeeded()
            semanticMemory.ensureIndexed(entries: startedEntries)
            applyInitialQuestionIfNeeded()
        }
        .onChange(of: messages) { _, newMessages in
            guard hasRestoredHistory else { return }
            FridayChatHistoryStore.save(newMessages)
        }
        .onChange(of: semanticMemory.lastSearchState) { _, state in
            if case .failed = state {
                indexErrorDismissed = false
            }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let height = (notification.object as? UIScreen)?.bounds.height ?? frame.maxY
            withOffRecordAnimation(OffRecordMotion.snappy) {
                screenHeight = height
                keyboardHeight = max(0, height - frame.minY)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
            withOffRecordAnimation(OffRecordMotion.snappy) {
                keyboardHeight = 0
            }
        }
        #endif
    }

    @ViewBuilder
    private func screenContent(contentWidth: CGFloat) -> some View {
        switch screenMode {
        case .activeChat:
            FridayActiveChatHeader(onNewChat: { isConfirmingNewChat = true })
            messageList(contentWidth: contentWidth)
            if showsStaticPrompts {
                FridayPromptSection(
                    title: String(localized: "Try Asking"),
                    questions: compactQuestions,
                    askedQuestions: askedQuestions,
                    layout: .grid,
                    action: askQuestion
                )
            }
        case .error:
            if messages.isEmpty {
                FridayChatErrorContent(
                    detail: activeError?.detail ?? "",
                    isIndexFailure: activeError?.question == nil,
                    onRetry: retryAfterError
                )
            } else {
                FridayActiveChatHeader(onNewChat: { isConfirmingNewChat = true })
                messageList(contentWidth: contentWidth)
                FridayChatErrorCard(
                    detail: activeError?.detail ?? "",
                    isIndexFailure: activeError?.question == nil,
                    onRetry: retryAfterError
                )
            }
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
        case .warmMinimal:
            FridayWarmMinimalContent(
                userName: authorName,
                questions: landingQuestions,
                askedQuestions: askedQuestions,
                mode: .warm,
                action: askQuestion
            )
        }
    }

    private func messageList(contentWidth: CGFloat) -> some View {
        FridayMessageList(
            messages: messages,
            isAnswering: isAnswering,
            revealingMessageID: revealingMessageID,
            showsFollowUps: !isAnswering && activeError == nil,
            bubbleMaxWidth: contentWidth * 0.78,
            namespace: evidenceNamespace,
            entryProvider: entry(for:),
            onRevealFinished: { id in
                if revealingMessageID == id {
                    revealingMessageID = nil
                }
            },
            onFollowUp: askFollowUp,
            onOpenEvidence: { selectedEvidence = $0 }
        )
    }

    private var screenMode: FridayChatScreenMode {
        if activeError != nil {
            return .error
        }
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

    /// A failed answer, or — on the landing screen — a journal index that could not be searched.
    private var activeError: FridayChatError? {
        if let chatError { return chatError }
        guard messages.isEmpty, !isAnswering, !semanticMemory.isBuilding, !indexErrorDismissed,
              startedEntries.count >= 5,
              case .failed(let detail) = semanticMemory.lastSearchState else { return nil }
        return FridayChatError(question: nil, profileSummary: nil, detail: detail)
    }

    /// Static prompts are a fallback; answers normally carry their own follow-ups.
    private var showsStaticPrompts: Bool {
        guard !isAnswering else { return false }
        guard let last = messages.last(where: { !$0.isUser }) else { return true }
        return last.followUps.isEmpty
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

    private var followUpFallbackQuestions: [FridayQuestion] {
        [.moodPattern, .stressTriggers, .happiestWhen, .talkAboutMost, .dominantTopics, .moodOverTime]
            .filter { !askedQuestions.contains($0) }
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .compact ? OffRecordSpacing.xxl : 40
    }

    private var topContentPadding: CGFloat {
        if screenMode == .activeChat || (screenMode == .error && !messages.isEmpty) {
            return horizontalSizeClass == .compact ? 82 : 72
        }
        return horizontalSizeClass == .compact ? 48 : 64
    }

    private var contentSpacing: CGFloat {
        switch screenMode {
        case .activeChat, .error: return 18
        default: return 0
        }
    }

    /// How far to raise the composer so it sits just above the keyboard. Measured against
    /// where this view actually ends on screen rather than an assumed safe area.
    private func keyboardLift(containerBottom: CGFloat) -> CGFloat {
        guard keyboardHeight > 0 else { return 0 }
        let keyboardTop = screenHeight - keyboardHeight
        let restingBottom = containerBottom - composerBottomClearance
        return max(0, restingBottom - (keyboardTop - OffRecordSpacing.sm))
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

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withOffRecordAnimation(OffRecordMotion.gentle) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    // MARK: History

    private func restoreHistoryIfNeeded() {
        guard !hasRestoredHistory else { return }
        let restored = FridayChatHistoryStore.load(resolving: entry(for:))
        if !restored.isEmpty {
            messages = restored
            let askedTexts = Set(restored.filter(\.isUser).map(\.summary))
            // Older history sent the rawValue as the message text.
            askedQuestions = Set(FridayQuestion.allCases.filter { askedTexts.contains($0.question) || askedTexts.contains($0.rawValue) })
        }
        hasRestoredHistory = true
    }

    private func startNewChat() {
        withOffRecordAnimation(OffRecordMotion.gentle) {
            messages = []
            askedQuestions = []
            chatError = nil
            revealingMessageID = nil
        }
        FridayChatHistoryStore.clear()
        newChatTrigger += 1
    }

    // MARK: Asking

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
        // The chat shows the question as written on the pill; the stable rawValue
        // stays the search query so retrieval matches what it always has.
        askEvidenceQuestion(
            question.question,
            searchQuery: question.rawValue,
            profileSummary: FridayResponseGenerator.generateResponse(for: question)
        )
        askedQuestions.insert(question)
    }

    private func askFollowUp(_ followUp: FridayFollowUp) {
        if let question = followUp.question {
            askQuestion(question)
        } else {
            askEvidenceQuestion(followUp.prompt, profileSummary: nil)
        }
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

    private func askEvidenceQuestion(_ question: String, searchQuery: String? = nil, profileSummary: String?) {
        guard !isAnswering else { return }
        chatError = nil
        messages.append(FridayChatMessage(text: question, isUser: true))
        answer(searchQuery ?? question, profileSummary: profileSummary)
    }

    private func retryAfterError() {
        guard let error = activeError else { return }
        if let question = error.question {
            chatError = nil
            answer(question, profileSummary: error.profileSummary)
        } else {
            indexErrorDismissed = true
            semanticMemory.rebuildIndex(entries: startedEntries)
        }
    }

    private func answer(_ question: String, profileSummary: String?) {
        guard !isAnswering else { return }
        isAnswering = true
        let entrySnapshot = startedEntries
        let askedPrompts = Set(messages.filter(\.isUser).map { $0.summary.lowercased() })

        Task {
            let answer = await EvidenceFridayEngine.answer(question: question, entries: entrySnapshot, profileSummary: profileSummary)

            if case .failed(let detail) = semanticMemory.lastSearchState,
               answer.evidence.isEmpty, answer.confidence == 0 {
                withOffRecordAnimation(OffRecordMotion.gentle) {
                    isAnswering = false
                    chatError = FridayChatError(question: question, profileSummary: profileSummary, detail: detail)
                }
                return
            }

            let followUps = FridayFollowUpBuilder.followUps(
                question: question,
                evidence: answer.evidence,
                knownNames: knownNames,
                askedPrompts: askedPrompts,
                fallbackQuestions: followUpFallbackQuestions
            )
            let fridayMessage = FridayChatMessage(
                summary: answer.summary,
                isUser: false,
                evidence: answer.evidence,
                observations: answer.observations,
                confidence: answer.confidence,
                limitations: answer.limitations,
                followUps: followUps
            )
            revealingMessageID = fridayMessage.id
            withOffRecordAnimation(OffRecordMotion.fade) {
                messages.append(fridayMessage)
                isAnswering = false
            }
            answerFeedbackTrigger += 1
        }
    }

    /// People, places, and themes Friday may suggest follow-ups about, most important first.
    /// `match` is the name as written in entries; `display` honors any rename.
    private var knownNames: [(match: String, display: String)] {
        let preferences = FridayMemoryPreferences.shared
        let graph = assistant.knowledgeGraph
        let ordered: [PersonalKnowledgeGraph.KnowledgeNode.NodeType] = [.person, .place, .topic]
        return ordered.flatMap { type in
            graph.topNodes(ofType: type, limit: 12)
                .filter { !preferences.isForgotten($0) }
                .map { (match: $0.label, display: preferences.displayName(for: $0)) }
        }
    }

    private func entry(for id: UUID) -> DiaryEntry? {
        startedEntries.first { $0.id == id }
    }
}

// MARK: - Error states

private struct FridayChatErrorCard: View {
    let detail: String
    let isIndexFailure: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            HStack(alignment: .top, spacing: OffRecordSpacing.md) {
                OffRecordIconBubble(
                    systemImage: "exclamationmark.bubble.fill",
                    tint: OffRecordColor.textCoral,
                    fill: OffRecordColor.backgroundBlushTint,
                    size: 36,
                    iconSize: 15
                )
                VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                    Text(isIndexFailure ? "I couldn’t read your journal." : "I couldn’t search your journal just now.")
                        .font(OffRecordTypography.labelLarge)
                        .foregroundStyle(OffRecordColor.textHeading)
                    Text("Try again in a moment.")
                        .font(OffRecordTypography.bodySmall)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: onRetry) {
                Label(isIndexFailure ? "Rebuild Index" : "Try Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textOnAccent, fill: OffRecordColor.brandLavenderDark))
            .accessibilityIdentifier("friday.error.retry")
        }
        .padding(OffRecordSpacing.lg)
        .offRecordCard(cornerRadius: OffRecordRadius.xl, fill: OffRecordColor.surfacePrimary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friday.error")
    }
}

private struct FridayChatErrorContent: View {
    let detail: String
    let isIndexFailure: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: OffRecordSpacing.xl) {
            FridayChatHeroHeader(subtitle: String(localized: "Something went wrong on my end. Your entries are fine."))

            FridayMascotView(pose: .thinking, size: 120)
                .accessibilityHidden(true)

            FridayChatErrorCard(detail: detail, isIndexFailure: isIndexFailure, onRetry: onRetry)
        }
    }
}

#Preview {
    NavigationStack {
        FridayChatView()
    }
}
