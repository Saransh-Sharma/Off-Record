//
//  EntryInsights.swift
//  OffRecord
//
//  What the entry's "From Friday" section shows: the entry's tone, the
//  feeling that stands out, what it's about, its topics, and one line from
//  Friday. Deterministic and model-free, built on the shared SentimentScorer
//  and EntityExtractor. Replaces the retired LocalAIEngine, which also
//  learned a second, unused profile every time this section opened.
//

import CoreData
import Foundation
import JournalFoundation
import SemanticMemoryKit

// MARK: - What the entry is about

enum EntryIntent: String, CaseIterable {
    case journaling = "journaling"
    case venting = "venting"
    case reflection = "reflection"
    case planning = "planning"
    case gratitude = "gratitude"
    case problemSolving = "problem_solving"
    case celebration = "celebration"
    case processing = "processing"
    case seeking = "seeking"
    case unknown = "unknown"

    var description: String {
        switch self {
        case .journaling: return String(localized: "Daily log")
        case .venting: return String(localized: "Venting")
        case .reflection: return String(localized: "Thinking it through")
        case .planning: return String(localized: "Planning")
        case .gratitude: return String(localized: "Gratitude")
        case .problemSolving: return String(localized: "Working through something")
        case .celebration: return String(localized: "Good news")
        case .processing: return String(localized: "Processing feelings")
        case .seeking: return String(localized: "Looking for advice")
        case .unknown: return String(localized: "General", comment: "What an entry is about, when no clear theme stands out.")
        }
    }

    var suggestedFollowUp: String {
        switch self {
        case .journaling: return String(localized: "How did that feel?")
        case .venting: return String(localized: "What would help right now?")
        case .reflection: return String(localized: "What stands out to you?")
        case .planning: return String(localized: "What’s a first small step?")
        case .gratitude: return String(localized: "How can you keep this feeling?")
        case .problemSolving: return String(localized: "Who could help?")
        case .celebration: return String(localized: "Who would you tell?")
        case .processing: return String(localized: "What did this teach you?")
        case .seeking: return String(localized: "What does your gut say?")
        case .unknown: return String(localized: "What else is on your mind?")
        }
    }
}

// MARK: - The feeling that stands out

enum EntryEmotion: String, CaseIterable {
    case joy = "joy"
    case sadness = "sadness"
    case anger = "anger"
    case fear = "fear"
    case surprise = "surprise"
    case disgust = "disgust"
    case anticipation = "anticipation"
    case trust = "trust"
    case neutral = "neutral"

    var representativeMood: Mood {
        switch self {
        case .joy: return .happy
        case .sadness: return .sad
        case .anger: return .angry
        case .fear: return .anxious
        case .surprise: return .excited
        case .disgust: return .angry
        case .anticipation: return .excited
        case .trust: return .grateful
        case .neutral: return .none
        }
    }

    var supportiveMessage: String {
        switch self {
        case .joy: return String(localized: "Sounds like a good day.")
        case .sadness: return String(localized: "That sounds hard.")
        case .anger: return String(localized: "That sounds frustrating.")
        case .fear: return String(localized: "That sounds scary.")
        case .surprise: return String(localized: "That was unexpected.")
        case .disgust: return String(localized: "That’s a lot to work through.")
        case .anticipation: return String(localized: "Sounds like you’re looking ahead.")
        case .trust: return String(localized: "Sounds like you have people to lean on.")
        case .neutral: return String(localized: "Sounds like a calm day.")
        }
    }
}

// MARK: - Result

struct EntryInsight: Equatable {
    let intent: EntryIntent
    let dominantEmotion: EntryEmotion
    /// The entry's tone, from -1 (heavy) to 1 (light).
    let sentiment: Double
    let topics: [String]
    /// Friday's one line. Heavy (gentle-mode) entries get the statement only, never a question.
    let fridayLine: String
}

// MARK: - Analyzer

enum EntryInsightAnalyzer {
    /// Keyword lists for the feeling that stands out.
    static let emotionKeywords: [EntryEmotion: Set<String>] = [
        .joy: ["happy", "excited", "glad", "wonderful", "amazing", "great", "love", "enjoy", "fantastic", "thrilled", "delighted", "blessed", "grateful", "awesome", "beautiful", "celebrate", "fun", "laugh", "smile", "proud"],
        .sadness: ["sad", "unhappy", "depressed", "lonely", "miss", "cry", "hurt", "disappointed", "grief", "sorrow", "heartbroken", "down", "blue", "melancholy", "lost", "empty", "hopeless", "tears", "mourning", "regret"],
        .anger: ["angry", "frustrated", "annoyed", "furious", "mad", "irritated", "hate", "resent", "rage", "upset", "bitter", "offended", "hostile", "outraged", "livid", "disgusted", "fed up", "pissed", "infuriated"],
        .fear: ["afraid", "scared", "worried", "anxious", "nervous", "terrified", "panic", "dread", "fear", "uneasy", "tense", "stressed", "overwhelmed", "paranoid", "insecure", "threatened", "alarmed", "frightened"],
        .surprise: ["surprised", "shocked", "amazed", "astonished", "unexpected", "wow", "unbelievable", "sudden", "startled", "stunned", "speechless", "incredible", "mind-blown"],
        .anticipation: ["hope", "expect", "looking forward", "planning", "excited about", "can't wait", "eager", "curious", "wondering", "future", "soon", "tomorrow", "next", "upcoming", "preparing"],
        .trust: ["trust", "believe", "faith", "confident", "reliable", "honest", "loyal", "support", "depend", "safe", "secure", "comfortable", "connected", "understood", "accepted"]
    ]

    /// Phrases that mark what the entry is about.
    static let intentPatterns: [EntryIntent: [String]] = [
        .venting: ["so frustrated", "can't believe", "hate when", "annoyed", "ugh", "terrible", "worst", "sick of", "fed up", "drives me crazy"],
        .gratitude: ["thankful", "grateful", "appreciate", "blessed", "lucky", "thank", "fortunate", "gift"],
        .planning: ["going to", "plan to", "want to", "need to", "should", "will", "goal", "tomorrow", "next week", "future"],
        .reflection: ["thinking about", "wonder", "realize", "understand now", "looking back", "in hindsight", "learned that", "means to me"],
        .celebration: ["excited", "finally", "achieved", "accomplished", "won", "got the", "made it", "success", "promotion", "accepted"],
        .problemSolving: ["how can i", "what should", "trying to figure", "solution", "problem is", "challenge", "struggling with", "need help"],
        .seeking: ["advice", "guidance", "help me", "what do you think", "should i", "confused about", "not sure"]
    ]

    /// - Parameters:
    ///   - responseMode: the entry's `SensitiveResponseMode`; `.gentle` drops the question.
    ///   - recurringTopic: returns the display name of a topic Friday has seen often, or nil.
    static func analyze(
        text: String,
        responseMode: SensitiveResponseMode = .normal,
        recurringTopic: (String) -> String? = { _ in nil }
    ) -> EntryInsight {
        let lowercased = text.lowercased()
        let sentiment = SentimentScorer.score(text)
        let emotion = dominantEmotion(in: lowercased)
        let intent = detectIntent(in: lowercased, sentiment: sentiment)
        let topics = topics(in: text)

        var parts = [emotion.supportiveMessage]
        if responseMode == .normal {
            parts.append(intent.suggestedFollowUp)
        }
        if let frequent = topics.lazy.compactMap(recurringTopic).first {
            parts.append(String(localized: "\(frequent) comes up a lot for you."))
        }

        return EntryInsight(
            intent: intent,
            dominantEmotion: emotion,
            sentiment: sentiment,
            topics: topics,
            fridayLine: parts.joined(separator: " ")
        )
    }

    /// Places, organizations, and nouns, most frequent first, capitalized for display.
    static func topics(in text: String, limit: Int = 10) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        func add(_ value: String) {
            let key = value.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { return }
            ordered.append(value)
        }
        for entity in EntityExtractor.namedEntities(in: text) where entity.kind != .person {
            add(entity.text)
        }
        let nouns = EntityExtractor.nouns(in: text, minimumLength: 4)
        let counts = Dictionary(grouping: nouns, by: { $0 }).mapValues(\.count)
        let firstIndex = Dictionary(nouns.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let ranked = counts.keys.sorted {
            if counts[$0] != counts[$1] { return counts[$0, default: 0] > counts[$1, default: 0] }
            return firstIndex[$0, default: 0] < firstIndex[$1, default: 0]
        }
        for noun in ranked {
            add(noun.capitalized)
        }
        return Array(ordered.prefix(limit))
    }

    static func dominantEmotion(in lowercasedText: String) -> EntryEmotion {
        let words = lowercasedText.split { !$0.isLetter && $0 != "'" && $0 != "\u{2019}" && $0 != "-" }.map(String.init)
        guard !words.isEmpty else { return .neutral }
        var scores: [EntryEmotion: Int] = [:]
        for word in words {
            for (emotion, keywords) in emotionKeywords where keywords.contains(word) {
                scores[emotion, default: 0] += 1
            }
        }
        // Stable tie-break in declaration order, so the same text always reads the same.
        let best = EntryEmotion.allCases
            .filter { $0 != .neutral }
            .max { scores[$0, default: 0] < scores[$1, default: 0] }
        guard let best, scores[best, default: 0] > 0 else { return .neutral }
        return best
    }

    static func detectIntent(in lowercasedText: String, sentiment: Double) -> EntryIntent {
        var scores: [EntryIntent: Int] = [:]
        for (intent, patterns) in intentPatterns {
            for pattern in patterns where lowercasedText.contains(pattern) {
                scores[intent, default: 0] += 1
            }
        }
        if sentiment < -0.3, scores[.venting, default: 0] > 0 {
            scores[.venting, default: 0] += 2
        }
        if sentiment > 0.3, scores[.celebration, default: 0] > 0 {
            scores[.celebration, default: 0] += 2
        }
        if lowercasedText.contains("?") {
            scores[.seeking, default: 0] += 1
        }
        let best = EntryIntent.allCases.max { scores[$0, default: 0] < scores[$1, default: 0] }
        guard let best, scores[best, default: 0] > 0 else { return .journaling }
        return best
    }
}

// MARK: - Retired profile

/// LocalAIEngine saved a second profile as an AIState row (`user_profile`),
/// and before that in UserDefaults. Nothing reads it any more, so it's
/// removed once rather than left behind.
enum RetiredEntryInsightProfile {
    static let stateType = "user_profile"
    static let legacyDefaultsKey = "userAIProfile"
    private static let cleanupDoneKey = "offrecord_retired_user_profile_removed"

    static func removeIfPresent(container: NSPersistentContainer, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: cleanupDoneKey) else { return }
        defaults.removeObject(forKey: legacyDefaultsKey)
        container.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "AIState")
            request.predicate = NSPredicate(format: "type == %@", stateType)
            guard let rows = try? context.fetch(request) else { return }
            rows.forEach(context.delete)
            do {
                if context.hasChanges { try context.save() }
                defaults.set(true, forKey: cleanupDoneKey)
            } catch {
                context.rollback()
            }
        }
    }
}
