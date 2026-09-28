//
//  FridayAssistantEngine.swift
//  OffRecord
//
//  Friday - a privacy-first assistant for personal reflection.
//
//  This engine builds a comprehensive personal model that learns:
//  - Your communication style and vocabulary patterns
//  - Emotional signatures and baseline states
//  - Thought patterns and cognitive tendencies
//  - Personal knowledge graph (people, places, topics, connections)
//  - Behavioral patterns (when you write, what triggers you)
//  - Predictive modeling (anticipating needs, moods, topics)
//
//  Everything stays on-device. Friday's understanding belongs to the user.
//
//  Based on:
//  - Mirror Neuron Theory (Rizzolatti, 1996)
//  - Personal Construct Theory (Kelly, 1955)
//  - Spreading Activation (Collins & Loftus, 1975)
//  - Circadian Rhythm Psychology
//

import Foundation
import NaturalLanguage
import CoreData
@_exported import KnowledgeGraphKit

// Profile and knowledge-graph types now live in KnowledgeGraphKit.

// MARK: - Friday Summary

/// A human-readable snapshot of Friday's current understanding.
struct FridaySummary: Codable {
    var personalitySnapshot: String = ""
    var communicationSnapshot: String = ""
    var emotionalSnapshot: String = ""
    var lifeSnapshot: String = ""
    var growthSnapshot: String = ""
    var lastUpdated: Date = Date()

    // Friday maturity (how much useful context Friday has)
    var maturityLevel: FridayMaturity = .nascent
    var dataPointsCollected: Int = 0

    enum FridayMaturity: String, Codable {
        case nascent = "nascent"        // < 5 entries
        case emerging = "emerging"      // 5-20 entries
        case developing = "developing"  // 20-50 entries
        case established = "established" // 50-100 entries
        case deep = "deep"              // 100+ entries

        /// Shown in the UI. Raw values are persisted in the saved summary, so they stay fixed.
        var displayName: String {
            switch self {
            case .nascent: return "New"
            case .emerging: return "Learning"
            case .developing: return "Growing"
            case .established: return "Solid"
            case .deep: return "Deep"
            }
        }

        var description: String {
            switch self {
            case .nascent: return "I’m just getting to know you."
            case .emerging: return "I’m starting to see patterns."
            case .developing: return "I’m getting a clearer picture."
            case .established: return "I know your patterns well."
            case .deep: return "I know you well."
            }
        }

        var progress: Double {
            switch self {
            case .nascent: return 0.1
            case .emerging: return 0.3
            case .developing: return 0.55
            case .established: return 0.8
            case .deep: return 1.0
            }
        }
    }
}

// MARK: - Friday Assistant Engine

@MainActor
final class FridayAssistantEngine: ObservableObject {

    static let shared = FridayAssistantEngine()

    // MARK: - Published State

    @Published var communicationStyle = CommunicationStyle()
    @Published var emotionalSignature = EmotionalSignature()
    @Published var thoughtPatterns = ThoughtPatterns()
    @Published var knowledgeGraph = PersonalKnowledgeGraph()
    @Published var behavioralPatterns = BehavioralPatterns()
    @Published var summary = FridaySummary()

    // NLP
    private let sentimentTagger = NLTagger(tagSchemes: [.sentimentScore])
    private let entityTagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
    private let tokenizer = NLTokenizer(unit: .word)
    private let sentenceTokenizer = NLTokenizer(unit: .sentence)

    // MARK: - Initialization

    private init() {
        load()
    }

    func resetForUITesting() {
        guard ProcessInfo.processInfo.arguments.contains("-UITesting") else { return }
        communicationStyle = CommunicationStyle()
        emotionalSignature = EmotionalSignature()
        thoughtPatterns = ThoughtPatterns()
        knowledgeGraph = PersonalKnowledgeGraph()
        behavioralPatterns = BehavioralPatterns()
        summary = FridaySummary()
    }

    // MARK: - Core Processing

    /// Process a diary entry to learn from it
    func processEntry(text: String, mood: String?, date: Date, duration: Double) {
        guard !text.isEmpty else { return }

        // Update all models
        analyzeCommunicationStyle(text)
        analyzeEmotionalSignature(text, mood: mood, date: date)
        analyzeThoughtPatterns(text)
        updateKnowledgeGraph(text, date: date)
        updateBehavioralPatterns(text, date: date, duration: duration)

        // Refresh summary
        updateSummary()

        // Persist
        save()
    }

    /// Re-process an edited entry — updates entity labels in the knowledge graph
    func reprocessEditedEntry(oldText: String, newText: String, mood: String?, date: Date, duration: Double) {
        guard !newText.isEmpty else { return }

        // Extract entities from old and new text to detect name changes
        let oldEntities = extractNamedEntities(from: oldText)
        let newEntities = extractNamedEntities(from: newText)

        // Find entities that were renamed (same position/context, different text)
        // Simple heuristic: if old had "Jhon" and new has "John", update the label
        for oldEntity in oldEntities {
            let oldKey = oldEntity.lowercased()
            if knowledgeGraph.nodes[oldKey] != nil {
                // Check if this entity is missing from new text
                let stillPresent = newEntities.contains { $0.lowercased() == oldKey }
                if !stillPresent {
                    // Look for a similar new entity that could be a correction
                    for newEntity in newEntities {
                        let newKey = newEntity.lowercased()
                        if knowledgeGraph.nodes[newKey] == nil && levenshteinSimilar(oldKey, newKey) {
                            // Transfer the old node data to the new key
                            if var node = knowledgeGraph.nodes[oldKey] {
                                node.label = newEntity
                                knowledgeGraph.nodes[newKey] = PersonalKnowledgeGraph.KnowledgeNode(
                                    id: newKey,
                                    label: newEntity,
                                    type: node.type,
                                    mentions: node.mentions,
                                    firstSeen: node.firstSeen,
                                    lastSeen: Date(),
                                    sentimentAssociation: node.sentimentAssociation,
                                    importance: node.importance
                                )
                                knowledgeGraph.nodes.removeValue(forKey: oldKey)
                                // Update edges too
                                for i in 0..<knowledgeGraph.edges.count {
                                    if knowledgeGraph.edges[i].from == oldKey {
                                        knowledgeGraph.edges[i].from = newKey
                                    }
                                    if knowledgeGraph.edges[i].to == oldKey {
                                        knowledgeGraph.edges[i].to = newKey
                                    }
                                }
                            }
                            break
                        }
                    }
                }
            }
        }

        // Now do the standard processing with new text
        processEntry(text: newText, mood: mood, date: date, duration: duration)
    }

    /// Extract named entities from text
    private func extractNamedEntities(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var entities: [String] = []
        entityTagger.string = text
        entityTagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace, .joinNames]) { tag, range in
            let entity = String(text[range])
            if entity.count > 1, tag == .personalName || tag == .placeName || tag == .organizationName {
                entities.append(entity)
            }
            return true
        }
        return entities
    }

    /// Check if two strings are similar enough to be a typo correction (Levenshtein distance <= 2)
    private func levenshteinSimilar(_ a: String, _ b: String) -> Bool {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count, n = bChars.count
        guard abs(m - n) <= 2 else { return false }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = aChars[i-1] == bChars[j-1] ? dp[i-1][j-1] : min(dp[i-1][j-1], dp[i-1][j], dp[i][j-1]) + 1
            }
        }
        return dp[m][n] <= 2 && dp[m][n] > 0
    }

    /// Process a chat message (lighter analysis)
    func processChatMessage(_ text: String) {
        guard !text.isEmpty else { return }
        analyzeCommunicationStyle(text)
        analyzeEmotionalSignature(text, mood: nil, date: Date())
        save()
    }

    // MARK: - Communication Style Analysis

    private func analyzeCommunicationStyle(_ text: String) {
        let n = Double(communicationStyle.analysisCount + 1)
        let alpha = 1.0 / n  // Running average weight

        // Tokenize
        let words = tokenizeWords(text)
        let sentences = tokenizeSentences(text)
        let uniqueWords = Set(words.map { $0.lowercased() })

        // Update word counts
        communicationStyle.totalWordsAnalyzed += words.count
        communicationStyle.totalSentencesAnalyzed += sentences.count
        communicationStyle.uniqueWordCount = max(communicationStyle.uniqueWordCount, uniqueWords.count)

        // Vocabulary richness (Type-Token Ratio)
        if words.count > 0 {
            let ttr = Double(uniqueWords.count) / Double(words.count)
            communicationStyle.vocabularyRichness = lerp(communicationStyle.vocabularyRichness, ttr, alpha)
        }

        // Sentence length
        if sentences.count > 0 {
            let avgLen = Double(words.count) / Double(sentences.count)
            communicationStyle.averageSentenceLength = lerp(communicationStyle.averageSentenceLength, avgLen, alpha)
        }

        // Expression patterns
        let exclamationRate = Double(text.filter { $0 == "!" }.count) / max(1, Double(sentences.count))
        let questionRate = Double(text.filter { $0 == "?" }.count) / max(1, Double(sentences.count))
        let hasEllipsis = text.contains("...") ? 1.0 : 0.0
        let capsWords = words.filter { $0 == $0.uppercased() && $0.count > 1 }.count
        let capsRate = Double(capsWords) / max(1, Double(words.count))

        communicationStyle.usesExclamations = lerp(communicationStyle.usesExclamations, min(1, exclamationRate), alpha)
        communicationStyle.usesQuestions = lerp(communicationStyle.usesQuestions, min(1, questionRate), alpha)
        communicationStyle.usesEllipsis = lerp(communicationStyle.usesEllipsis, hasEllipsis, alpha)
        communicationStyle.usesAllCaps = lerp(communicationStyle.usesAllCaps, min(1, capsRate), alpha)
        communicationStyle.averageMessageLength = lerp(communicationStyle.averageMessageLength, Double(words.count), alpha)

        // Formality detection
        let informalWords = Set(["gonna", "wanna", "kinda", "yeah", "nah", "lol", "haha", "omg", "wtf", "tbh", "idk", "ngl", "fr", "rn", "ugh", "yep", "nope", "hey", "yo", "dude", "bruh"])
        let informalCount = words.filter { informalWords.contains($0.lowercased()) }.count
        let informalRate = Double(informalCount) / max(1, Double(words.count))
        communicationStyle.formalityLevel = lerp(communicationStyle.formalityLevel, max(0, 1.0 - informalRate * 10), alpha)

        // Expressiveness (exclamations + caps + emotion words)
        let expressiveScore = min(1, exclamationRate + capsRate + Double(informalCount) * 0.1)
        communicationStyle.expressiveness = lerp(communicationStyle.expressiveness, expressiveScore, alpha)

        // Directness (short sentences, few hedging words)
        let hedgingWords = Set(["maybe", "perhaps", "might", "could", "sort of", "kind of", "i think", "i guess", "probably", "possibly"])
        let hedgingCount = words.filter { hedgingWords.contains($0.lowercased()) }.count
        let directnessScore = max(0, 1.0 - Double(hedgingCount) / max(1, Double(words.count)) * 20)
        communicationStyle.directness = lerp(communicationStyle.directness, directnessScore, alpha)

        // Track signature words (filter stopwords and common words)
        let significantWords = words.filter { $0.count > 3 && !Self.commonWords.contains($0.lowercased()) }
        for word in significantWords {
            communicationStyle.signatureWords[word.lowercased(), default: 0] += 1
        }
        // Keep only top 100 signature words
        if communicationStyle.signatureWords.count > 150 {
            let sorted = communicationStyle.signatureWords.sorted { $0.value > $1.value }
            communicationStyle.signatureWords = Dictionary(uniqueKeysWithValues: Array(sorted.prefix(100)))
        }

        communicationStyle.analysisCount += 1
    }

    // MARK: - Emotional Signature Analysis

    private func analyzeEmotionalSignature(_ text: String, mood: String?, date: Date) {
        let n = Double(emotionalSignature.analysisCount + 1)
        let alpha = 1.0 / n

        // Sentiment
        sentimentTagger.string = text
        let (tag, _) = sentimentTagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        let sentiment = Double(tag?.rawValue ?? "0") ?? 0

        // Update baseline
        emotionalSignature.baselineValence = lerp(emotionalSignature.baselineValence, sentiment, alpha)

        // Track sentiment history
        emotionalSignature.recentSentiments.append(sentiment)
        if emotionalSignature.recentSentiments.count > 30 {
            emotionalSignature.recentSentiments.removeFirst()
        }

        // Calculate trend
        if emotionalSignature.recentSentiments.count >= 5 {
            let recent = Array(emotionalSignature.recentSentiments.suffix(5))
            let older = Array(emotionalSignature.recentSentiments.prefix(min(5, emotionalSignature.recentSentiments.count)))
            let recentAvg = recent.reduce(0, +) / Double(recent.count)
            let olderAvg = older.reduce(0, +) / Double(older.count)
            emotionalSignature.sentimentTrend = recentAvg - olderAvg
        }

        // Emotional range (standard deviation of recent sentiments)
        if emotionalSignature.recentSentiments.count > 2 {
            let mean = emotionalSignature.recentSentiments.reduce(0, +) / Double(emotionalSignature.recentSentiments.count)
            let variance = emotionalSignature.recentSentiments.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(emotionalSignature.recentSentiments.count)
            emotionalSignature.emotionalRange = min(1, sqrt(variance) * 2)
        }

        // Time-based mood
        let hour = Calendar.current.component(.hour, from: date)
        let weekday = Calendar.current.component(.weekday, from: date)

        if hour < 12 {
            emotionalSignature.morningMood = lerp(emotionalSignature.morningMood, sentiment, alpha)
        } else {
            emotionalSignature.eveningMood = lerp(emotionalSignature.eveningMood, sentiment, alpha)
        }

        if weekday >= 2 && weekday <= 6 {
            emotionalSignature.weekdayMood = lerp(emotionalSignature.weekdayMood, sentiment, alpha)
        } else {
            emotionalSignature.weekendMood = lerp(emotionalSignature.weekendMood, sentiment, alpha)
        }

        // Track mood frequency
        if let mood = mood {
            emotionalSignature.emotionFrequency[mood, default: 0] += 1
        }

        // Extract topics and associate with sentiment
        let topics = extractTopicWords(text)
        for topic in topics {
            if sentiment > 0.2 {
                emotionalSignature.positiveTriggersTopics[topic, default: 0] += sentiment
            } else if sentiment < -0.2 {
                emotionalSignature.negativeTriggersTopics[topic, default: 0] += abs(sentiment)
            }
        }

        // Trim trigger maps
        if emotionalSignature.positiveTriggersTopics.count > 50 {
            let sorted = emotionalSignature.positiveTriggersTopics.sorted { $0.value > $1.value }
            emotionalSignature.positiveTriggersTopics = Dictionary(uniqueKeysWithValues: Array(sorted.prefix(30)))
        }
        if emotionalSignature.negativeTriggersTopics.count > 50 {
            let sorted = emotionalSignature.negativeTriggersTopics.sorted { $0.value > $1.value }
            emotionalSignature.negativeTriggersTopics = Dictionary(uniqueKeysWithValues: Array(sorted.prefix(30)))
        }

        emotionalSignature.analysisCount += 1
    }

    // MARK: - Thought Pattern Analysis

    private func analyzeThoughtPatterns(_ text: String) {
        let lowercased = text.lowercased()
        let words = tokenizeWords(text)
        let n = Double(thoughtPatterns.analysisCount + 1)
        let alpha = 1.0 / n

        // Analytical vs Emotional
        let analyticalWords = Set(["because", "therefore", "reason", "analyze", "logic", "evidence", "data", "think", "consider", "evaluate", "compare", "conclude", "hypothesis"])
        let emotionalWords = Set(["feel", "feeling", "felt", "heart", "soul", "love", "hate", "miss", "hurt", "joy", "pain", "emotion", "mood", "vibe"])
        let analyticalCount = words.filter { analyticalWords.contains($0.lowercased()) }.count
        let emotionalCount = words.filter { emotionalWords.contains($0.lowercased()) }.count
        let total = max(1, analyticalCount + emotionalCount)
        let analyticalRatio = Double(analyticalCount) / Double(total)
        thoughtPatterns.analyticalScore = lerp(thoughtPatterns.analyticalScore, analyticalRatio, alpha)

        // Abstract vs Concrete
        let abstractWords = Set(["concept", "idea", "meaning", "purpose", "philosophy", "theory", "wonder", "imagine", "dream", "possibility", "abstract", "metaphor"])
        let concreteWords = Set(["did", "went", "ate", "bought", "made", "saw", "met", "talked", "worked", "drove", "walked", "called"])
        let abstractCount = words.filter { abstractWords.contains($0.lowercased()) }.count
        let concreteCount = words.filter { concreteWords.contains($0.lowercased()) }.count
        let acTotal = max(1, abstractCount + concreteCount)
        thoughtPatterns.abstractScore = lerp(thoughtPatterns.abstractScore, Double(abstractCount) / Double(acTotal), alpha)

        // Time orientation
        let futureWords = Set(["will", "going to", "plan", "goal", "hope", "tomorrow", "next", "future", "soon", "want to", "someday", "ahead"])
        let pastWords = Set(["was", "were", "had", "used to", "remember", "ago", "yesterday", "last", "before", "back then", "once"])
        let futureCount = words.filter { futureWords.contains($0.lowercased()) }.count
        let pastCount = words.filter { pastWords.contains($0.lowercased()) }.count
        let timeTotal = max(1, futureCount + pastCount)
        thoughtPatterns.futureOriented = lerp(thoughtPatterns.futureOriented, Double(futureCount) / Double(timeTotal), alpha)

        // Self-focus (I/me/my vs they/them/others)
        let selfWords = words.filter { ["i", "me", "my", "myself", "i'm", "i've", "i'd", "i'll"].contains($0.lowercased()) }.count
        let otherWords = words.filter { ["they", "them", "their", "he", "she", "we", "people", "everyone", "someone"].contains($0.lowercased()) }.count
        let focusTotal = max(1, selfWords + otherWords)
        thoughtPatterns.selfFocused = lerp(thoughtPatterns.selfFocused, Double(selfWords) / Double(focusTotal), alpha)

        // Growth mindset indicators
        let growthWords = Set(["learn", "grow", "improve", "better", "progress", "develop", "understand", "realize", "change", "adapt", "try"])
        let fixedWords = Set(["can't", "impossible", "never", "always", "stuck", "hopeless", "pointless", "useless"])
        let growthCount = words.filter { growthWords.contains($0.lowercased()) }.count
        let fixedCount = words.filter { fixedWords.contains($0.lowercased()) }.count
        let mindsetTotal = max(1, growthCount + fixedCount)
        thoughtPatterns.growthMindsetScore = lerp(thoughtPatterns.growthMindsetScore, Double(growthCount) / Double(mindsetTotal), alpha)

        // Self-awareness
        let awarenessWords = Set(["i realize", "i notice", "i'm aware", "i see now", "i understand", "pattern", "tendency", "habit"])
        let hasAwareness = awarenessWords.contains { lowercased.contains($0) } ? 0.8 : 0.3
        thoughtPatterns.selfAwarenessLevel = lerp(thoughtPatterns.selfAwarenessLevel, hasAwareness, alpha)

        // Gratitude
        let gratitudeWords = Set(["grateful", "thankful", "appreciate", "blessed", "lucky", "gift"])
        let hasGratitude = words.contains { gratitudeWords.contains($0.lowercased()) } ? 0.8 : 0.2
        thoughtPatterns.gratitudeTendency = lerp(thoughtPatterns.gratitudeTendency, hasGratitude, alpha)

        thoughtPatterns.analysisCount += 1
    }

    // MARK: - Knowledge Graph Update

    // Words/suffixes that indicate an entity is NOT a person
    private static let nonPersonSuffixes = Set([
        "festival", "fest", "day", "week", "month", "park", "museum", "temple",
        "church", "mosque", "building", "tower", "bridge", "street", "road",
        "avenue", "square", "station", "airport", "school", "university",
        "hospital", "market", "mall", "store", "restaurant", "cafe", "hotel",
        "lake", "river", "mountain", "beach", "island", "ocean", "sea",
        "city", "town", "village", "country", "state", "county",
        "christmas", "easter", "diwali", "eid", "hanukkah", "thanksgiving",
        "ramadan", "halloween", "valentine", "pongal", "holi", "navratri",
        "onam", "vishu", "bihu", "lohri", "makar", "sankranti", "deepavali"
    ])

    private static let nonPersonExact = Set([
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july",
        "august", "september", "october", "november", "december",
        "iphone", "ipad", "mac", "apple", "google", "amazon", "netflix",
        "instagram", "whatsapp", "facebook", "twitter", "youtube",
        "covid", "corona", "birthday", "anniversary", "wedding", "funeral",
        "new year", "new years"
    ])

    /// Check if an entity tagged as personalName is likely not a person
    private func isLikelyNotPerson(_ entity: String) -> Bool {
        let lower = entity.lowercased()
        // Check exact match
        if Self.nonPersonExact.contains(lower) { return true }
        // Check if any word in the entity is a non-person suffix
        let words = lower.split(separator: " ").map { String($0) }
        for word in words {
            if Self.nonPersonSuffixes.contains(word) { return true }
        }
        return false
    }

    private func updateKnowledgeGraph(_ text: String, date: Date) {
        let sentiment = getSentiment(text)

        // Extract entities
        entityTagger.string = text
        var extractedPeople: [String] = []
        var extractedPlaces: [String] = []
        var extractedTopics: [String] = []

        entityTagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace, .joinNames]) { tag, range in
            let entity = String(text[range])
            guard entity.count > 1 else { return true }

            switch tag {
            case .personalName:
                // Validate: filter out places, festivals, objects mis-tagged as people
                if isLikelyNotPerson(entity) {
                    // Re-classify as place or topic based on suffix
                    let lower = entity.lowercased()
                    let words = lower.split(separator: " ").map { String($0) }
                    let hasPlaceSuffix = words.contains { Self.nonPersonSuffixes.intersection(["park", "museum", "temple", "church", "mosque", "building", "tower", "bridge", "street", "road", "avenue", "square", "station", "airport", "lake", "river", "mountain", "beach", "island", "city", "town", "village", "country"]).contains($0) }
                    if hasPlaceSuffix {
                        extractedPlaces.append(entity)
                        knowledgeGraph.addOrUpdate(id: entity, label: entity, type: .place, sentiment: sentiment)
                    } else {
                        extractedTopics.append(entity)
                        knowledgeGraph.addOrUpdate(id: entity, label: entity, type: .topic, sentiment: sentiment)
                    }
                } else {
                    extractedPeople.append(entity)
                    knowledgeGraph.addOrUpdate(id: entity, label: entity, type: .person, sentiment: sentiment)
                }
            case .placeName:
                extractedPlaces.append(entity)
                knowledgeGraph.addOrUpdate(id: entity, label: entity, type: .place, sentiment: sentiment)
            case .organizationName:
                knowledgeGraph.addOrUpdate(id: entity, label: entity, type: .topic, sentiment: sentiment)
                extractedTopics.append(entity)
            default:
                break
            }
            return true
        }

        // Extract topic words
        let topicWords = extractTopicWords(text)
        for word in topicWords.prefix(5) {
            knowledgeGraph.addOrUpdate(id: word, label: word.capitalized, type: .topic, sentiment: sentiment)
            extractedTopics.append(word)
        }

        // Detect goals/fears/values
        let lowercased = text.lowercased()
        if lowercased.contains("i want to") || lowercased.contains("my goal") || lowercased.contains("dream of") {
            for topic in topicWords.prefix(2) {
                knowledgeGraph.addOrUpdate(id: "goal:\(topic)", label: topic.capitalized, type: .goal, sentiment: 0.5)
            }
        }
        if lowercased.contains("afraid of") || lowercased.contains("scares me") || lowercased.contains("worried about") {
            for topic in topicWords.prefix(2) {
                knowledgeGraph.addOrUpdate(id: "fear:\(topic)", label: topic.capitalized, type: .fear, sentiment: -0.5)
            }
        }

        // Build connections between entities mentioned together
        let allEntities = extractedPeople + extractedPlaces + extractedTopics
        for i in 0..<allEntities.count {
            for j in (i+1)..<min(allEntities.count, i + 4) {
                knowledgeGraph.connect(allEntities[i], to: allEntities[j])
            }
        }
    }

    // MARK: - Behavioral Pattern Update

    private func updateBehavioralPatterns(_ text: String, date: Date, duration: Double) {
        let words = tokenizeWords(text)
        let hour = Calendar.current.component(.hour, from: date)
        let weekday = Calendar.current.component(.weekday, from: date)
        let n = Double(behavioralPatterns.analysisCount + 1)
        let alpha = 1.0 / n

        behavioralPatterns.hourlyActivity[hour, default: 0] += 1
        behavioralPatterns.dayOfWeekActivity[weekday, default: 0] += 1
        behavioralPatterns.totalEntries += 1
        behavioralPatterns.totalWords += words.count
        behavioralPatterns.averageWordsPerEntry = lerp(behavioralPatterns.averageWordsPerEntry, Double(words.count), alpha)
        behavioralPatterns.averageSessionLength = lerp(behavioralPatterns.averageSessionLength, Double(words.count), alpha)

        // Peak hour/day
        behavioralPatterns.peakHour = behavioralPatterns.hourlyActivity.max(by: { $0.value < $1.value })?.key
        behavioralPatterns.peakDay = behavioralPatterns.dayOfWeekActivity.max(by: { $0.value < $1.value })?.key

        // Weekly tracking
        let weekKey = Self.weekFormatter.string(from: date)
        behavioralPatterns.weeklyEntryHistory[weekKey, default: 0] += 1

        // Voice preference
        if duration > 0 {
            behavioralPatterns.prefersVoice = lerp(behavioralPatterns.prefersVoice, 0.8, alpha)
        } else {
            behavioralPatterns.prefersVoice = lerp(behavioralPatterns.prefersVoice, 0.2, alpha)
        }

        // Entry length preference
        let shortThreshold = 50
        if words.count < shortThreshold {
            behavioralPatterns.prefersShortEntries = lerp(behavioralPatterns.prefersShortEntries, 0.8, alpha)
        } else {
            behavioralPatterns.prefersShortEntries = lerp(behavioralPatterns.prefersShortEntries, 0.2, alpha)
        }

        behavioralPatterns.analysisCount += 1
    }

    // MARK: - Summary Generation

    private func updateSummary() {
        let totalDataPoints = behavioralPatterns.totalEntries

        // Update maturity
        if totalDataPoints >= 100 {
            summary.maturityLevel = .deep
        } else if totalDataPoints >= 50 {
            summary.maturityLevel = .established
        } else if totalDataPoints >= 20 {
            summary.maturityLevel = .developing
        } else if totalDataPoints >= 5 {
            summary.maturityLevel = .emerging
        } else {
            summary.maturityLevel = .nascent
        }
        summary.dataPointsCollected = totalDataPoints

        // Personality snapshot
        var traits: [String] = []
        if communicationStyle.expressiveness > 0.6 { traits.append("expressive") }
        else if communicationStyle.expressiveness < 0.3 { traits.append("reserved") }
        if communicationStyle.directness > 0.6 { traits.append("direct") }
        else if communicationStyle.directness < 0.3 { traits.append("thoughtful") }
        if communicationStyle.formalityLevel < 0.3 { traits.append("casual") }
        else if communicationStyle.formalityLevel > 0.7 { traits.append("articulate") }
        if thoughtPatterns.analyticalScore > 0.6 { traits.append("analytical") }
        if thoughtPatterns.growthMindsetScore > 0.6 { traits.append("growth-oriented") }
        if thoughtPatterns.gratitudeTendency > 0.5 { traits.append("grateful") }

        summary.personalitySnapshot = traits.isEmpty ? "Still learning." : "You come across as \(traits.formatted(.list(type: .and)))."

        // Communication snapshot
        if communicationStyle.analysisCount > 3 {
            let wordStyle = communicationStyle.averageSentenceLength > 15 ? "in detail" : "briefly"
            let toneStyle = communicationStyle.expressiveness > 0.5 ? "with feeling" : "evenly"
            summary.communicationSnapshot = "You write \(wordStyle) and \(toneStyle). About \(Int(communicationStyle.averageSentenceLength)) words per sentence."
        }

        // Emotional snapshot
        if emotionalSignature.analysisCount > 3 {
            let valenceLabel = emotionalSignature.baselineValence > 0.1 ? "mostly positive" : (emotionalSignature.baselineValence < -0.1 ? "mostly low" : "mixed")
            let trendLabel = emotionalSignature.sentimentTrend > 0.05 ? "improving" : (emotionalSignature.sentimentTrend < -0.05 ? "dipping" : "holding steady")
            summary.emotionalSnapshot = "Your mood is \(valenceLabel) and \(trendLabel)."
        }

        // Life snapshot
        let topPeople = knowledgeGraph.topNodes(ofType: .person, limit: 3)
        let topTopics = knowledgeGraph.topNodes(ofType: .topic, limit: 3)
        var lifeItems: [String] = []
        if !topPeople.isEmpty {
            lifeItems.append("People: \(topPeople.map { $0.label }.joined(separator: ", ")).")
        }
        if !topTopics.isEmpty {
            lifeItems.append("Topics: \(topTopics.map { $0.label }.joined(separator: ", ")).")
        }
        summary.lifeSnapshot = lifeItems.joined(separator: " ")

        // Growth snapshot
        if behavioralPatterns.totalEntries > 5 {
            let consistency = behavioralPatterns.consistencyScore > 0.5 ? "regularly" : "now and then"
            summary.growthSnapshot = String(AttributedString(localized: "^[\(behavioralPatterns.totalEntries) entry](inflect: true) so far. You write \(consistency).").characters)
        }

        summary.lastUpdated = Date()
    }

    // MARK: - Search Suggestions

    struct SearchSuggestion {
        let text: String
        let type: String  // "person", "topic", "place", "mood"
        let icon: String
    }

    /// Search knowledge graph for suggestions matching query
    func searchSuggestions(for query: String) -> [SearchSuggestion] {
        guard query.count >= 2 else { return [] }
        let lowered = query.lowercased()
        var results: [SearchSuggestion] = []

        // Search knowledge graph nodes
        for node in knowledgeGraph.nodes.values {
            if node.label.lowercased().contains(lowered) {
                let icon: String
                switch node.type {
                case .person: icon = "person.fill"
                case .place: icon = "mappin.circle.fill"
                case .topic: icon = "tag.fill"
                case .goal: icon = "star.fill"
                case .fear: icon = "exclamationmark.triangle.fill"
                default: icon = "doc.text"
                }
                results.append(SearchSuggestion(text: node.label, type: node.type.rawValue, icon: icon))
            }
        }

        // Search mood names
        let moodNames = ["happy", "calm", "grateful", "excited", "tired", "anxious", "sad", "angry"]
        for mood in moodNames {
            if mood.contains(lowered) {
                results.append(SearchSuggestion(text: mood.capitalized, type: "mood", icon: "face.smiling"))
            }
        }

        return Array(results.prefix(8))
    }

    // MARK: - Friday Predictions

    /// Predict what the user might want to talk about
    func predictTopics() -> [String] {
        // Based on recurring topics and time patterns
        var suggestions: [String] = []

        // Recent high-importance topics
        let recentTopics = knowledgeGraph.topNodes(ofType: .topic, limit: 3)
        suggestions.append(contentsOf: recentTopics.map { $0.label })

        // Unresolved situations (topics with negative sentiment that keep recurring)
        let negativeTopics = emotionalSignature.negativeTriggersTopics
            .sorted { $0.value > $1.value }
            .prefix(2)
            .map { $0.key.capitalized }
        suggestions.append(contentsOf: negativeTopics)

        return Array(Set(suggestions)).prefix(5).map { $0 }
    }

    /// Predict the user's current emotional state based on patterns
    func predictMood(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let weekday = Calendar.current.component(.weekday, from: date)

        var predictedSentiment = emotionalSignature.baselineValence

        if hour < 12 {
            predictedSentiment = emotionalSignature.morningMood
        } else {
            predictedSentiment = emotionalSignature.eveningMood
        }

        if weekday >= 2 && weekday <= 6 {
            predictedSentiment = (predictedSentiment + emotionalSignature.weekdayMood) / 2
        } else {
            predictedSentiment = (predictedSentiment + emotionalSignature.weekendMood) / 2
        }

        if predictedSentiment > 0.3 { return "positive" }
        if predictedSentiment > 0.1 { return "calm" }
        if predictedSentiment > -0.1 { return "neutral" }
        if predictedSentiment > -0.3 { return "reflective" }
        return "needs support"
    }

    // MARK: - NLP Helpers

    private func tokenizeWords(_ text: String) -> [String] {
        var words: [String] = []
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            words.append(String(text[range]))
            return true
        }
        return words
    }

    private func tokenizeSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        sentenceTokenizer.string = text
        sentenceTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }
        return sentences
    }

    private func extractTopicWords(_ text: String) -> [String] {
        var topics: [String] = []
        entityTagger.string = text
        entityTagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            if tag == .noun {
                let word = String(text[range]).lowercased()
                if word.count > 3 && !Self.commonWords.contains(word) {
                    topics.append(word)
                }
            }
            return true
        }
        return topics
    }

    private func getSentiment(_ text: String) -> Double {
        sentimentTagger.string = text
        let (tag, _) = sentimentTagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        return Double(tag?.rawValue ?? "0") ?? 0
    }

    private func lerp(_ from: Double, _ to: Double, _ t: Double) -> Double {
        return from + (to - from) * t
    }

    // MARK: - Persistence

    private struct FridayPayload: Codable {
        var communicationStyle: CommunicationStyle
        var emotionalSignature: EmotionalSignature
        var thoughtPatterns: ThoughtPatterns
        var knowledgeGraph: PersonalKnowledgeGraph
        var behavioralPatterns: BehavioralPatterns
        var summary: FridaySummary
    }

    private func save() {
        let payload = FridayPayload(
            communicationStyle: communicationStyle,
            emotionalSignature: emotionalSignature,
            thoughtPatterns: thoughtPatterns,
            knowledgeGraph: knowledgeGraph,
            behavioralPatterns: behavioralPatterns,
            summary: summary
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let context = PersistenceController.shared.container.newBackgroundContext()
        context.perform {
            let request = NSFetchRequest<AIState>(entityName: "AIState")
            request.predicate = NSPredicate(format: "type == %@", "friday_assistant")
            let existing = try? context.fetch(request).first

            let state = existing ?? AIState(context: context)
            if existing == nil {
                state.id = UUID()
                state.type = "friday_assistant"
            }
            state.payload = data
            state.updatedAt = Date()
            try? context.save()
        }
    }

    private func load() {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<AIState>(entityName: "AIState")
        request.predicate = NSPredicate(format: "type IN %@", ["friday_assistant", "digital_twin"])
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \AIState.updatedAt, ascending: false)
        ]

        if let state = try? context.fetch(request).first, let data = state.payload {
            let decoder = JSONDecoder()
            if let payload = try? decoder.decode(FridayPayload.self, from: data) {
                communicationStyle = payload.communicationStyle
                emotionalSignature = payload.emotionalSignature
                thoughtPatterns = payload.thoughtPatterns
                knowledgeGraph = payload.knowledgeGraph
                behavioralPatterns = payload.behavioralPatterns
                summary = payload.summary
                // The snapshot sentences are derived copy, so rebuild them from the loaded
                // models; otherwise a saved summary keeps old wording until the next entry.
                updateSummary()
                if state.type == "digital_twin" {
                    save()
                }
                return
            }
        }

        // One-time migration from UserDefaults
        let decoder = JSONDecoder()
        var migrated = false
        if let data = UserDefaults.standard.data(forKey: "dt_commStyle"),
           let val = try? decoder.decode(CommunicationStyle.self, from: data) { communicationStyle = val; migrated = true }
        if let data = UserDefaults.standard.data(forKey: "dt_emotionalSig"),
           let val = try? decoder.decode(EmotionalSignature.self, from: data) { emotionalSignature = val; migrated = true }
        if let data = UserDefaults.standard.data(forKey: "dt_thoughtPatterns"),
           let val = try? decoder.decode(ThoughtPatterns.self, from: data) { thoughtPatterns = val; migrated = true }
        if let data = UserDefaults.standard.data(forKey: "dt_knowledgeGraph"),
           let val = try? decoder.decode(PersonalKnowledgeGraph.self, from: data) { knowledgeGraph = val; migrated = true }
        if let data = UserDefaults.standard.data(forKey: "dt_behavioral"),
           let val = try? decoder.decode(BehavioralPatterns.self, from: data) { behavioralPatterns = val; migrated = true }
        if let data = UserDefaults.standard.data(forKey: "dt_summary"),
           let val = try? decoder.decode(FridaySummary.self, from: data) { summary = val; migrated = true }

        if migrated {
            save()
            for key in ["dt_commStyle", "dt_emotionalSig", "dt_thoughtPatterns", "dt_knowledgeGraph", "dt_behavioral", "dt_summary"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Static

    private static let weekFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-'W'ww"
        return f
    }()

    private static let commonWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
        "be", "have", "has", "had", "do", "does", "did", "will", "would",
        "could", "should", "may", "might", "must", "shall", "can", "need",
        "this", "that", "these", "those", "i", "you", "he", "she", "it",
        "we", "they", "what", "which", "who", "when", "where", "why", "how",
        "all", "each", "every", "both", "few", "more", "most", "other",
        "some", "such", "no", "nor", "not", "only", "own", "same", "so",
        "than", "too", "very", "just", "also", "now", "here", "there",
        "about", "like", "really", "much", "still", "well", "back", "even",
        "then", "thing", "things", "know", "think", "want", "get", "got",
        "going", "make", "made", "come", "came", "take", "took", "give",
        "gave", "tell", "told", "say", "said", "good", "time", "day"
    ]
}
