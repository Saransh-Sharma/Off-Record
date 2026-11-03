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
    // MARK: Go Deeper and titles

    /// Every golden case in `FridayGroundingGoldens`, the same set the iOS 27 evaluation runs.
    @Test(arguments: FridayGroundingGoldens.questions + FridayGroundingGoldens.titles)
    func goldenCase(_ golden: GroundingGolden) {
        guard !golden.needsPartOfSpeechModel || FridayGroundingGoldens.hasPartOfSpeechModel else { return }
        #expect(golden.validate() == golden.shown, "\(golden.kind.rawValue): \(golden.note): \(golden.raw)")
    }

    @Test func goldensCoverBothVerdictsForEachKind() {
        for kind in [GroundingGolden.Kind.question, .title] {
            let cases = (FridayGroundingGoldens.questions + FridayGroundingGoldens.titles).filter { $0.kind == kind }
            #expect(cases.contains { $0.shown != nil })
            #expect(cases.contains { $0.shown == nil })
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
