//
//  FridayChatFormattingTests.swift
//  OffRecordTests
//
//  Deterministic helpers behind Friday's answers: citation markers,
//  evidence-strength labels, and follow-up suggestions.
//

import Testing
import Foundation
@testable import OffRecord

@MainActor
struct FridayChatFormattingTests {
    private func evidence(
        _ id: String,
        entryID: UUID = UUID(),
        daysAgo: Int = 0,
        mood: String? = "anxious",
        snippet: String = "Work felt heavy today."
    ) -> EvidenceReference {
        EvidenceReference(
            id: id,
            entryID: entryID,
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            mood: mood,
            snippet: snippet,
            chunkText: snippet,
            score: 0.03,
            matchReason: .meaning
        )
    }

    @Test func observationsCarryCitationNumbersMatchingEvidenceOrder() {
        let items = [evidence("a"), evidence("b"), evidence("c")]
        let segments = FridayAnswerComposer.segments(
            summary: "Work comes up a lot. It often feels heavy.",
            observations: [
                EvidenceObservation(text: "Deadlines show up twice.", evidenceIDs: ["c", "a"]),
                EvidenceObservation(text: "No citation here.", evidenceIDs: ["missing"])
            ],
            evidence: items
        )

        #expect(segments.count == 4)
        #expect(segments[0].citations.isEmpty)
        #expect(segments[2].citations == [1, 3])
        #expect(segments[3].citations.isEmpty)
        #expect(FridayAnswerComposer.plainText(segments).contains("[") == false)
    }

    @Test func evidenceStrengthReflectsConfidenceAndDistinctEntries() {
        let shared = UUID()
        #expect(FridayEvidenceStrength.assess(confidence: 0.8, evidence: [evidence("a"), evidence("b"), evidence("c")]) == .strong(entries: 3))
        #expect(FridayEvidenceStrength.assess(confidence: 0.8, evidence: [evidence("a", entryID: shared), evidence("b", entryID: shared)]) == .tentative(entries: 1))
        #expect(FridayEvidenceStrength.assess(confidence: 0.57, evidence: [evidence("a"), evidence("b")]) == .some(entries: 2))
        #expect(FridayEvidenceStrength.assess(confidence: 0.45, evidence: []) == .overallPatterns)
        #expect(FridayEvidenceStrength.assess(confidence: 0, evidence: []) == nil)
        #expect(FridayEvidenceStrength.strong(entries: 4).title == "Strong evidence · 4 entries")
    }

    @Test func followUpsComeFromEvidenceAndSkipWhatWasAsked() {
        let items = [
            evidence("a", daysAgo: 30, snippet: "Maya helped me prep for the review."),
            evidence("b", daysAgo: 1, snippet: "Still anxious about the review.")
        ]
        let followUps = FridayFollowUpBuilder.followUps(
            question: "What did I write about work stress?",
            evidence: items,
            knownNames: [(match: "Maya", display: "Maya"), (match: "Work", display: "Work")],
            askedPrompts: [],
            fallbackQuestions: [.moodPattern]
        )

        #expect(followUps.count == FridayFollowUpBuilder.maximumCount)
        #expect(followUps[0].prompt == "What else have I written about Maya?")
        #expect(followUps[1].prompt == "When else did I feel anxious?")
        #expect(followUps[2].prompt.hasPrefix("How has this changed since"))
    }

    @Test func followUpsFallBackToUnaskedQuestionsWithoutEvidence() {
        let followUps = FridayFollowUpBuilder.followUps(
            question: "Anything about scuba diving?",
            evidence: [],
            knownNames: [],
            askedPrompts: [FridayQuestion.moodPattern.rawValue.lowercased()],
            fallbackQuestions: [.moodPattern, .stressTriggers, .talkAboutMost]
        )

        #expect(followUps.map(\.question) == [.stressTriggers, .talkAboutMost])
    }

    @Test func renamedPeopleKeepTheirWrittenNameForRetrieval() {
        let followUps = FridayFollowUpBuilder.followUps(
            question: "How was the weekend?",
            evidence: [evidence("a", snippet: "Dinner with Sam was lovely.")],
            knownNames: [(match: "Sam", display: "Samantha")],
            askedPrompts: [],
            fallbackQuestions: []
        )

        #expect(followUps.first?.title == "More about Samantha")
        #expect(followUps.first?.prompt == "What else have I written about Sam?")
    }
}
