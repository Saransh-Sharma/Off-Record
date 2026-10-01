import Foundation
import JournalFoundation
import Testing
@testable import OffRecord

/// Golden cases for model-written text: what a question, a title, or a chat
/// answer may say about an entry. No model runs here; each case is the raw
/// text a model could return and whether Friday may show it.
@MainActor
@Suite(.serialized)
struct FridayGroundingTests {
    private let lunch = "Lunch with Maya by the lake. We talked about her new job in Lisbon and the move in spring."
    private let deadline = "The project deadline moved again and my manager wants the review by Friday."

    /// Topic checks need the part-of-speech model, which some simulators lack.
    private var hasPartOfSpeechModel: Bool {
        !EntityExtractor.nouns(in: "The project deadline moved again.").isEmpty
    }

    // MARK: Go Deeper

    @Test func groundedQuestionsPass() {
        let accepted: [(entry: String, raw: String, shown: String)] = [
            (lunch, "What did Maya say about the job in Lisbon?", "What did Maya say about the job in Lisbon?"),
            (lunch, "\"What did Maya's news about Lisbon change for you?\"", "What did Maya’s news about Lisbon change for you?"),
            (lunch, "  What would the move to Lisbon change?  ", "What would the move to Lisbon change?"),
            (deadline, "What would make the review with your manager easier?", "What would make the review with your manager easier?"),
            (deadline, "What does the deadline change for your Friday?", "What does the deadline change for your Friday?"),
        ]
        for item in accepted {
            let context = EntryGenerationContext(text: item.entry, mood: .calm)
            #expect(GoDeeperQuestionValidator.validated(item.raw, context: context) == item.shown, "\(item.raw)")
        }
    }

    @Test func ungroundedOrOffVoiceQuestionsFail() {
        let context = EntryGenerationContext(text: lunch, mood: .calm)
        let rejected = [
            "What did Priya say about the job?",                      // invented name
            "What Did Maya Say About Lisbon?",                        // Title Case
            "What did Maya say? How was the lake?",                   // two questions
            "What did Maya say about Lisbon",                         // no question mark
            "What did I notice about Maya and Lisbon?",               // Friday talking about herself
            "What does your journey with Maya mean now?",             // banned word
            "Is there a diagnosis for how Maya made you feel?",       // clinical
            "What did Maya say about the new job in Lisbon this spring?", // 12 words
            "Why does Lisbon matter so much!",                        // exclamation
            "What do you need right now?",                            // not about the entry
            "Why?",                                                   // too short
            "What did Maya say about Lisbon — and why?",              // em dash
        ]
        for raw in rejected {
            #expect(GoDeeperQuestionValidator.validated(raw, context: context) == nil, "\(raw)")
        }
    }

    @Test func inventedTopicsFailWhenTheTaggerCanTell() {
        guard hasPartOfSpeechModel else { return }
        let context = EntryGenerationContext(text: lunch, mood: .calm)
        #expect(GoDeeperQuestionValidator.validated("How did the beach trip with Maya feel?", context: context) == nil)
        #expect(GoDeeperQuestionValidator.validated("What did Maya say about her wedding plans?", context: context) == nil)
    }

    @Test func assessmentPhrasesFail() {
        let context = EntryGenerationContext(text: deadline, mood: .anxious)
        #expect(GoDeeperQuestionValidator.validated("Why do you think you are anxious about the deadline?", context: context) == nil)
        #expect(GoDeeperQuestionValidator.validated("What do you need to change about the review?", context: context) == nil)
        #expect(GoDeeperQuestionValidator.validated("What would you change about the review?", context: context) != nil)
    }

    // MARK: Titles

    @Test func groundedTitlesPass() {
        let context = EntryGenerationContext(text: lunch, mood: .happy)
        let accepted: [(raw: String, shown: String)] = [
            ("Lunch with Maya by the lake", "Lunch with Maya by the lake"),
            ("Maya's new job in Lisbon", "Maya’s new job in Lisbon"),
            ("Lunch with Maya.", "Lunch with Maya"),
            ("\"A move to Lisbon\"", "A move to Lisbon"),
        ]
        for item in accepted {
            #expect(EntryTitleValidator.validated(item.raw, context: context) == item.shown, "\(item.raw)")
        }
    }

    @Test func offVoiceTitlesFail() {
        let context = EntryGenerationContext(text: lunch, mood: .happy)
        let rejected = [
            "Lunch With Maya",                                        // Title Case
            "A long lunch with Maya and her new job by the lake",     // too long
            "Lunch with Priya",                                       // invented name
            "My lunch with Maya",                                     // pronoun
            "Lunch with Maya!",                                       // exclamation
            "Healing journey with Maya",                              // banned
            "Maya",                                                   // one word
            "Lunch with Maya: Lisbon",                                // inner punctuation
            "Clinical notes on Maya",                                 // clinical
        ]
        for raw in rejected {
            #expect(EntryTitleValidator.validated(raw, context: context) == nil, "\(raw)")
        }
    }

    // MARK: Shared checks

    @Test func validatorFlagsVoiceAndSafetyRules() {
        #expect(FridayOutputValidator.isAcceptable("Work came up in 3 entries."))
        #expect(!FridayOutputValidator.isAcceptable("I noticed work came up a lot."))
        #expect(!FridayOutputValidator.isAcceptable("Friday noticed a pattern."))
        #expect(!FridayOutputValidator.isAcceptable("Here’s what stands out."))
        #expect(!FridayOutputValidator.isAcceptable("This sounds like a disorder."))
        #expect(!FridayOutputValidator.isAcceptable("You have burnout from work."))
        #expect(!FridayOutputValidator.isAcceptable("Work felt great 🎉"))
        #expect(!FridayOutputValidator.isAcceptable("You wrote about wanting to end it all."))
        // A heavy question may be echoed back in a chat answer, but never high-risk wording.
        #expect(!FridayOutputValidator.isAcceptable("Work felt hopeless after the review."))
        #expect(FridayOutputValidator.isAcceptable("Work felt hopeless after the review.", allowedRisk: .moderateConcern))
        #expect(!FridayOutputValidator.isAcceptable("You wrote about suicide.", allowedRisk: .moderateConcern))
        // Whole words only: "validate" and "adjust" aren't "valid" and "just".
        #expect(FridayOutputValidator.isAcceptable("You wanted to validate the plan and adjust it."))
    }

    @Test func normalizingCurlsApostrophesAndUnwrapsQuotes() {
        #expect(FridayOutputValidator.normalized("  \u{201C}Don't stop.\u{201D} ") == "Don’t stop.")
        #expect(FridayOutputValidator.normalized("Two\n spaces...") == "Two spaces…")
    }

    @Test func chatAnswerValidatorRejectsClinicalWordingAndUncitedIDs() {
        let evidence = [EvidenceReference(
            id: "e1", entryID: UUID(), date: Date(), mood: "anxious",
            snippet: "Work pressure was heavy after the meeting.",
            chunkText: "Work pressure was heavy after the meeting.",
            score: 0.03, matchReason: .exact
        )]
        func answer(summary: String, ids: [String]) -> EvidenceBackedFridayAnswer {
            EvidenceBackedFridayAnswer(
                summary: summary,
                observations: [EvidenceObservation(text: "Work pressure came up after a meeting.", evidenceIDs: ids)],
                evidence: evidence, confidence: 0.6, followUpPrompt: "Want to talk?", limitations: nil
            )
        }
        let good = FridayAnswerValidator.validated(answer(summary: "Work pressure shows up in 1 entry.", ids: ["e1"]), question: "work pressure", evidence: evidence)
        #expect(good?.summary == "Work pressure shows up in 1 entry.")
        #expect(good?.followUpPrompt == nil)
        #expect(FridayAnswerValidator.validated(answer(summary: "These are symptoms of stress.", ids: ["e1"]), question: "work pressure", evidence: evidence) == nil)
        #expect(FridayAnswerValidator.validated(answer(summary: "Work pressure shows up.", ids: ["e9"]), question: "work pressure", evidence: evidence) == nil)
        #expect(FridayAnswerValidator.validated(answer(summary: "The meeting ran late because Arjun pushed it.", ids: ["e1"]), question: "work pressure", evidence: evidence) == nil)
    }
}
