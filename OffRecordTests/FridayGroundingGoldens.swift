import Foundation
@testable import OffRecord

/// One golden case: text a model could return about an entry, and what Friday
/// shows for it (nil when it must be rejected). Shared by the Swift Testing
/// suite (iOS 26) and the Evaluations suite (iOS 27).
struct GroundingGolden: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case question
        case title
    }

    let kind: Kind
    let entry: String
    let raw: String
    /// What the person sees; nil means the validator must reject `raw`.
    let shown: String?
    /// Why the case exists, for failure messages.
    let note: String
    /// Topic checks need NaturalLanguage's part-of-speech model, which some simulators lack.
    var needsPartOfSpeechModel = false

    /// Runs the validator for this case's kind.
    func validate() -> String? {
        switch kind {
        case .question:
            return GoDeeperQuestionValidator.validated(raw, context: EntryGenerationContext(text: entry, mood: .calm))
        case .title:
            return EntryTitleValidator.validated(raw, context: EntryGenerationContext(text: entry, mood: .calm))
        }
    }
}

enum FridayGroundingGoldens {
    static let lunch = "Lunch with Maya by the lake. We talked about her new job in Lisbon and the move in spring."
    static let deadline = "The project deadline moved again and my manager wants the review by Friday."

    static var hasPartOfSpeechModel: Bool {
        !EntityExtractor.nouns(in: "The project deadline moved again.").isEmpty
    }

    /// Cases that can run here: topic cases are dropped without a part-of-speech model.
    static var runnable: [GroundingGolden] {
        let all = questions + titles
        return hasPartOfSpeechModel ? all : all.filter { !$0.needsPartOfSpeechModel }
    }

    static let questions: [GroundingGolden] = [
        q(lunch, "What did Maya say about the job in Lisbon?", shown: "What did Maya say about the job in Lisbon?", "names from the entry"),
        q(lunch, "\"What did Maya's news about Lisbon change for you?\"", shown: "What did Maya’s news about Lisbon change for you?", "quotes unwrapped, apostrophe curled"),
        q(lunch, "  What would the move to Lisbon change?  ", shown: "What would the move to Lisbon change?", "whitespace trimmed"),
        q(deadline, "What would make the review with your manager easier?", shown: "What would make the review with your manager easier?", "topics from the entry"),
        q(deadline, "What does the deadline change for your Friday?", shown: "What does the deadline change for your Friday?", "weekday capitals allowed"),
        q(deadline, "What would you change about the review?", shown: "What would you change about the review?", "plain question"),
        q(lunch, "What did Priya say about the job?", shown: nil, "invented name"),
        q(lunch, "What Did Maya Say About Lisbon?", shown: nil, "Title Case"),
        q(lunch, "What did Maya say? How was the lake?", shown: nil, "two questions"),
        q(lunch, "What did Maya say about Lisbon", shown: nil, "no question mark"),
        q(lunch, "What did I notice about Maya and Lisbon?", shown: nil, "Friday talking about herself"),
        q(lunch, "What does your journey with Maya mean now?", shown: nil, "banned word"),
        q(lunch, "Is there a diagnosis for how Maya made you feel?", shown: nil, "clinical term"),
        q(lunch, "What did Maya say about the new job in Lisbon this spring?", shown: nil, "12 words"),
        q(lunch, "Why does Lisbon matter so much!", shown: nil, "exclamation"),
        q(lunch, "What do you need right now?", shown: nil, "not about the entry"),
        q(lunch, "Why?", shown: nil, "too short"),
        q(lunch, "What did Maya say about Lisbon — and why?", shown: nil, "em dash"),
        q(deadline, "Why do you think you are anxious about the deadline?", shown: nil, "assessment of the person"),
        q(deadline, "What do you need to change about the review?", shown: nil, "advice pattern"),
        q(lunch, "How did the beach trip with Maya feel?", shown: nil, "invented topic", needsPartOfSpeechModel: true),
        q(lunch, "What did Maya say about her wedding plans?", shown: nil, "invented topic", needsPartOfSpeechModel: true),
    ]

    static let titles: [GroundingGolden] = [
        t(lunch, "Lunch with Maya by the lake", shown: "Lunch with Maya by the lake", "names and topics from the entry"),
        t(lunch, "Maya's new job in Lisbon", shown: "Maya’s new job in Lisbon", "apostrophe curled"),
        t(lunch, "Lunch with Maya.", shown: "Lunch with Maya", "trailing period dropped"),
        t(lunch, "\"A move to Lisbon\"", shown: "A move to Lisbon", "quotes unwrapped"),
        t(lunch, "Lunch With Maya", shown: nil, "Title Case"),
        t(lunch, "A long lunch with Maya and her new job by the lake", shown: nil, "too long"),
        t(lunch, "Lunch with Priya", shown: nil, "invented name"),
        t(lunch, "My lunch with Maya", shown: nil, "pronoun"),
        t(lunch, "Lunch with Maya!", shown: nil, "exclamation"),
        t(lunch, "Healing journey with Maya", shown: nil, "banned word"),
        t(lunch, "Maya", shown: nil, "one word"),
        t(lunch, "Lunch with Maya: Lisbon", shown: nil, "inner punctuation"),
        t(lunch, "Clinical notes on Maya", shown: nil, "clinical term"),
    ]

    private static func q(_ entry: String, _ raw: String, shown: String?, _ note: String, needsPartOfSpeechModel: Bool = false) -> GroundingGolden {
        GroundingGolden(kind: .question, entry: entry, raw: raw, shown: shown, note: note, needsPartOfSpeechModel: needsPartOfSpeechModel)
    }

    private static func t(_ entry: String, _ raw: String, shown: String?, _ note: String) -> GroundingGolden {
        GroundingGolden(kind: .title, entry: entry, raw: raw, shown: shown, note: note)
    }
}
