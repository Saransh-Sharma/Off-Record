//
//  LocalAIEngine.swift
//  OffRecord
//
//  On-device AI engine for personal assistant capabilities.
//  All processing happens locally using CoreML and NaturalLanguage frameworks.
//  No data is ever sent to external servers.
//
//  Capabilities:
//  - Intent recognition from voice/text
//  - Contextual understanding based on user history
//  - Personalized insights and suggestions
//  - Emotion and sentiment tracking
//  - Topic extraction and categorization
//  - Smart reminders and proactive assistance
//

import Foundation
import NaturalLanguage
import CoreML
import CoreData

// MARK: - User Profile (Local Learning)

/// Stores learned preferences and patterns about the user locally
final class UserProfile: ObservableObject, Codable {
    
    // MARK: - Stored Properties
    
    var commonTopics: [String: Int] = [:]
    var emotionalPatterns: [String: [EmotionEntry]] = [:]
    var writingTimes: [Int: Int] = [:] // Hour -> count
    var averageSentiment: Double = 0.0
    var totalEntries: Int = 0
    var preferredMoods: [String: Int] = [:]
    var importantPeople: [String: Int] = [:]
    var importantPlaces: [String: Int] = [:]
    var goalsAndAspirations: [String] = []
    var recurringThemes: [String: Int] = [:]
    var weeklyMoodTrend: [Double] = []
    
    // MARK: - Nested Types
    
    struct EmotionEntry: Codable {
        let date: Date
        let sentiment: Double
        let dominantEmotion: String
    }
    
    // MARK: - Persistence

    private static let profileKey = "userAIProfile"
    private static let coreDataType = "user_profile"

    static func load() -> UserProfile {
        // Try Core Data first
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<AIState>(entityName: "AIState")
        request.predicate = NSPredicate(format: "type == %@", coreDataType)
        if let state = try? context.fetch(request).first,
           let data = state.payload,
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            return profile
        }

        // One-time migration from UserDefaults
        guard let data = UserDefaults.standard.data(forKey: profileKey),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return UserProfile()
        }
        profile.save()
        UserDefaults.standard.removeObject(forKey: profileKey)
        return profile
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.perform {
            let request = NSFetchRequest<AIState>(entityName: "AIState")
            request.predicate = NSPredicate(format: "type == %@", UserProfile.coreDataType)
            let existing = try? context.fetch(request).first
            let state = existing ?? AIState(context: context)
            if existing == nil {
                state.id = UUID()
                state.type = UserProfile.coreDataType
            }
            state.payload = data
            state.updatedAt = Date()
            try? context.save()
        }
    }
}

// MARK: - Intent Recognition

enum UserIntent: String, CaseIterable {
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

// MARK: - Emotion Detection

enum DetectedEmotion: String, CaseIterable {
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

// MARK: - AI Analysis Result

struct AIAnalysisResult {
    let intent: UserIntent
    let emotions: [DetectedEmotion: Double]
    let dominantEmotion: DetectedEmotion
    let sentiment: Double // -1.0 to 1.0
    let topics: [String]
    let people: [String]
    let places: [String]
    let suggestedResponse: String
    let keywords: [String]
    let complexity: TextComplexity
    
    enum TextComplexity {
        case simple, moderate, complex
    }
}

// MARK: - Local AI Engine

/// Main AI engine that processes all user data locally using CoreML and NaturalLanguage
final class LocalAIEngine: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = LocalAIEngine()
    
    // MARK: - Properties
    
    @Published var userProfile: UserProfile
    @Published var isProcessing = false
    
    private let sentimentTagger: NLTagger
    private let entityTagger: NLTagger
    private let tokenizer: NLTokenizer
    private let languageRecognizer: NLLanguageRecognizer
    
    // Emotion keyword dictionaries for local classification
    private let emotionKeywords: [DetectedEmotion: Set<String>] = [
        .joy: ["happy", "excited", "glad", "wonderful", "amazing", "great", "love", "enjoy", "fantastic", "thrilled", "delighted", "blessed", "grateful", "awesome", "beautiful", "celebrate", "fun", "laugh", "smile", "proud"],
        .sadness: ["sad", "unhappy", "depressed", "lonely", "miss", "cry", "hurt", "disappointed", "grief", "sorrow", "heartbroken", "down", "blue", "melancholy", "lost", "empty", "hopeless", "tears", "mourning", "regret"],
        .anger: ["angry", "frustrated", "annoyed", "furious", "mad", "irritated", "hate", "resent", "rage", "upset", "bitter", "offended", "hostile", "outraged", "livid", "disgusted", "fed up", "pissed", "infuriated"],
        .fear: ["afraid", "scared", "worried", "anxious", "nervous", "terrified", "panic", "dread", "fear", "uneasy", "tense", "stressed", "overwhelmed", "paranoid", "insecure", "threatened", "alarmed", "frightened"],
        .surprise: ["surprised", "shocked", "amazed", "astonished", "unexpected", "wow", "unbelievable", "sudden", "startled", "stunned", "speechless", "incredible", "mind-blown"],
        .anticipation: ["hope", "expect", "looking forward", "planning", "excited about", "can't wait", "eager", "curious", "wondering", "future", "soon", "tomorrow", "next", "upcoming", "preparing"],
        .trust: ["trust", "believe", "faith", "confident", "reliable", "honest", "loyal", "support", "depend", "safe", "secure", "comfortable", "connected", "understood", "accepted"]
    ]
    
    // Intent detection patterns
    private let intentPatterns: [UserIntent: [String]] = [
        .venting: ["so frustrated", "can't believe", "hate when", "annoyed", "ugh", "terrible", "worst", "sick of", "fed up", "drives me crazy"],
        .gratitude: ["thankful", "grateful", "appreciate", "blessed", "lucky", "thank", "fortunate", "gift"],
        .planning: ["going to", "plan to", "want to", "need to", "should", "will", "goal", "tomorrow", "next week", "future"],
        .reflection: ["thinking about", "wonder", "realize", "understand now", "looking back", "in hindsight", "learned that", "means to me"],
        .celebration: ["excited", "finally", "achieved", "accomplished", "won", "got the", "made it", "success", "promotion", "accepted"],
        .problemSolving: ["how can i", "what should", "trying to figure", "solution", "problem is", "challenge", "struggling with", "need help"],
        .seeking: ["advice", "guidance", "help me", "what do you think", "should i", "confused about", "not sure"]
    ]
    
    // MARK: - Initialization
    
    private init() {
        self.userProfile = UserProfile.load()
        self.sentimentTagger = NLTagger(tagSchemes: [.sentimentScore])
        self.entityTagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        self.tokenizer = NLTokenizer(unit: .word)
        self.languageRecognizer = NLLanguageRecognizer()
    }
    
    // MARK: - Main Analysis Function
    
    /// Analyzes text completely on-device and returns comprehensive AI insights
    func analyze(text: String) -> AIAnalysisResult {
        isProcessing = true
        defer { isProcessing = false }
        
        let lowercasedText = text.lowercased()
        
        // Perform all analyses
        let sentiment = analyzeSentiment(text)
        let emotions = detectEmotions(lowercasedText)
        let dominantEmotion = emotions.max(by: { $0.value < $1.value })?.key ?? .neutral
        let intent = detectIntent(lowercasedText)
        let entities = extractEntities(text)
        let keywords = extractKeywords(text)
        let complexity = assessComplexity(text)
        
        // Generate personalized response
        let response = generateResponse(
            intent: intent,
            emotion: dominantEmotion,
            sentiment: sentiment,
            topics: entities.topics
        )
        
        // Update user profile with learnings
        updateProfile(
            sentiment: sentiment,
            emotion: dominantEmotion,
            topics: entities.topics,
            people: entities.people,
            places: entities.places
        )
        
        return AIAnalysisResult(
            intent: intent,
            emotions: emotions,
            dominantEmotion: dominantEmotion,
            sentiment: sentiment,
            topics: entities.topics,
            people: entities.people,
            places: entities.places,
            suggestedResponse: response,
            keywords: keywords,
            complexity: complexity
        )
    }
    
    // MARK: - Sentiment Analysis
    
    private func analyzeSentiment(_ text: String) -> Double {
        sentimentTagger.string = text
        let (sentiment, _) = sentimentTagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        return Double(sentiment?.rawValue ?? "0") ?? 0.0
    }
    
    // MARK: - Emotion Detection
    
    private func detectEmotions(_ text: String) -> [DetectedEmotion: Double] {
        var emotionScores: [DetectedEmotion: Double] = [:]
        
        // Initialize all emotions with base score
        for emotion in DetectedEmotion.allCases {
            emotionScores[emotion] = 0.0
        }
        
        // Tokenize and check against emotion keywords
        tokenizer.string = text
        var wordCount = 0
        
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()
            wordCount += 1
            
            for (emotion, keywords) in self.emotionKeywords {
                if keywords.contains(word) {
                    emotionScores[emotion, default: 0.0] += 1.0
                }
            }
            return true
        }
        
        // Normalize scores
        if wordCount > 0 {
            for emotion in emotionScores.keys {
                emotionScores[emotion] = min(1.0, (emotionScores[emotion] ?? 0) / Double(max(1, wordCount / 10)))
            }
        }
        
        // If no emotions detected, mark as neutral
        let totalScore = emotionScores.values.reduce(0, +)
        if totalScore < 0.1 {
            emotionScores[.neutral] = 1.0
        }
        
        return emotionScores
    }
    
    // MARK: - Intent Detection
    
    private func detectIntent(_ text: String) -> UserIntent {
        var intentScores: [UserIntent: Int] = [:]
        
        for (intent, patterns) in intentPatterns {
            for pattern in patterns {
                if text.contains(pattern) {
                    intentScores[intent, default: 0] += 1
                }
            }
        }
        
        // Additional intent signals based on sentiment and structure
        let sentiment = analyzeSentiment(text)
        
        if sentiment < -0.3 && intentScores[.venting] ?? 0 > 0 {
            intentScores[.venting, default: 0] += 2
        }
        
        if sentiment > 0.3 && intentScores[.celebration] ?? 0 > 0 {
            intentScores[.celebration, default: 0] += 2
        }
        
        // Check for question patterns (seeking)
        if text.contains("?") {
            intentScores[.seeking, default: 0] += 1
        }
        
        // Default to journaling if no strong signal
        return intentScores.max(by: { $0.value < $1.value })?.key ?? .journaling
    }
    
    // MARK: - Entity Extraction
    
    private func extractEntities(_ text: String) -> (topics: [String], people: [String], places: [String]) {
        entityTagger.string = text
        
        var topics: Set<String> = []
        var people: Set<String> = []
        var places: Set<String> = []
        
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        
        entityTagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            let entity = String(text[range])
            
            switch tag {
            case .personalName:
                people.insert(entity)
            case .placeName:
                places.insert(entity)
            case .organizationName:
                topics.insert(entity)
            default:
                break
            }
            return true
        }
        
        // Extract nouns as potential topics
        entityTagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            if tag == .noun {
                let noun = String(text[range])
                if noun.count > 3 { // Filter short words
                    topics.insert(noun.capitalized)
                }
            }
            return true
        }
        
        return (Array(topics.prefix(10)), Array(people), Array(places))
    }
    
    // MARK: - Keyword Extraction
    
    private func extractKeywords(_ text: String) -> [String] {
        entityTagger.string = text
        var keywords: [String: Int] = [:]
        
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]
        
        entityTagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            if tag == .noun || tag == .verb || tag == .adjective {
                let word = String(text[range]).lowercased()
                if word.count > 3 && !Self.stopWords.contains(word) {
                    keywords[word, default: 0] += 1
                }
            }
            return true
        }
        
        return keywords.sorted { $0.value > $1.value }.prefix(10).map { $0.key }
    }
    
    // MARK: - Text Complexity Assessment
    
    private func assessComplexity(_ text: String) -> AIAnalysisResult.TextComplexity {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        let words = text.split { $0.isWhitespace }
        
        let avgWordsPerSentence = sentences.isEmpty ? 0 : Double(words.count) / Double(sentences.count)
        let avgWordLength = words.isEmpty ? 0 : Double(words.reduce(0) { $0 + $1.count }) / Double(words.count)
        
        if avgWordsPerSentence > 20 && avgWordLength > 6 {
            return .complex
        } else if avgWordsPerSentence > 12 || avgWordLength > 5 {
            return .moderate
        }
        return .simple
    }
    
    // MARK: - Response Generation
    
    private func generateResponse(intent: UserIntent, emotion: DetectedEmotion, sentiment: Double, topics: [String]) -> String {
        var response = emotion.supportiveMessage
        
        // Add intent-specific follow-up
        response += " " + intent.suggestedFollowUp
        
        // Personalize based on user history
        if userProfile.totalEntries > 10 {
            if let frequentTopic = topics.first(where: { userProfile.commonTopics[$0, default: 0] > 3 }) {
                response += " " + String(localized: "\(frequentTopic) comes up a lot for you.")
            }
        }
        
        return response
    }
    
    // MARK: - Profile Learning
    
    private func updateProfile(sentiment: Double, emotion: DetectedEmotion, topics: [String], people: [String], places: [String]) {
        // Update topic frequency
        for topic in topics {
            userProfile.commonTopics[topic, default: 0] += 1
        }
        
        // Update people and places
        for person in people {
            userProfile.importantPeople[person, default: 0] += 1
        }
        for place in places {
            userProfile.importantPlaces[place, default: 0] += 1
        }
        
        // Track emotional patterns
        let entry = UserProfile.EmotionEntry(
            date: Date(),
            sentiment: sentiment,
            dominantEmotion: emotion.rawValue
        )
        
        let dayKey = Self.dayFormatter.string(from: Date())
        userProfile.emotionalPatterns[dayKey, default: []].append(entry)
        
        // Update writing time preference
        let hour = Calendar.current.component(.hour, from: Date())
        userProfile.writingTimes[hour, default: 0] += 1
        
        // Update running average sentiment
        let oldTotal = userProfile.averageSentiment * Double(userProfile.totalEntries)
        userProfile.totalEntries += 1
        userProfile.averageSentiment = (oldTotal + sentiment) / Double(userProfile.totalEntries)
        
        // Save profile
        userProfile.save()
    }
    
    // MARK: - Helpers
    
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
        "be", "have", "has", "had", "do", "does", "did", "will", "would",
        "could", "should", "may", "might", "must", "shall", "can", "need",
        "this", "that", "these", "those", "i", "you", "he", "she", "it",
        "we", "they", "what", "which", "who", "when", "where", "why", "how",
        "all", "each", "every", "both", "few", "more", "most", "other",
        "some", "such", "no", "nor", "not", "only", "own", "same", "so",
        "than", "too", "very", "just", "also", "now", "here", "there"
    ]
}
