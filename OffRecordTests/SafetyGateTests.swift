import CoreData
import Foundation
import JournalFoundation
import Testing
@testable import OffRecord

/// Every AI surface must route self-harm content to support copy instead of
/// analysis or quotes (`SensitiveDomainPolicy`, "Safety" in OffRecord Design.md).
@MainActor
@Suite(.serialized)
struct SafetyGateTests {

    // MARK: Friday chat

    @Test func highRiskQuestionGetsSupportWithoutEvidence() async {
        let answer = await EvidenceFridayEngine.answer(
            question: "Why do I want to hurt myself?",
            evidence: [evidence("e1", "I want to hurt myself when work piles up.", score: 0.05)]
        )

        #expect(answer.responseMode == .supportOnly)
        #expect(answer.summary == FridayPersonality.riskSafeSupport)
        #expect(answer.evidence.isEmpty)
        #expect(answer.observations.isEmpty)
        #expect(answer.followUpPrompt == nil)
    }

    @Test func highRiskEvidenceIsNeverQuoted() async {
        let safe = evidence("safe", "Work pressure was heavy after the meeting.", score: 0.03, reason: .exact)
        let risky = evidence("risky", "After the meeting I thought about suicide.", score: 0.04, reason: .exact)

        let answer = await EvidenceFridayEngine.answer(question: "work pressure", evidence: [risky, safe])

        #expect(answer.responseMode == .normal)
        #expect(answer.evidence.map(\.id) == ["safe"])
        #expect(answer.observations.allSatisfy { !$0.evidenceIDs.contains("risky") })
    }

    @Test func onlyHighRiskEvidenceGetsSupportInsteadOfAnAnswer() async {
        let risky = evidence("risky", "Everyone would be better off without me.", score: 0.05, reason: .exact)

        let answer = await EvidenceFridayEngine.answer(question: "How was last week?", evidence: [risky])

        #expect(answer.responseMode == .supportOnly)
        #expect(answer.evidence.isEmpty)
    }

    @Test func weakHighRiskMatchesDoNotTurnAQuestionIntoSupport() async {
        let weak = evidence("weak", "I thought about suicide that night.", score: 0.004)

        let answer = await EvidenceFridayEngine.answer(question: "How was the trip to Goa?", evidence: [weak])

        #expect(answer.responseMode == .normal)
        #expect(answer.evidence.isEmpty)
        #expect(answer.summary != FridayPersonality.riskSafeSupport)
    }

    @Test func hopelessQuestionStillAnswersGently() async {
        let safe = evidence("safe", "Work felt hopeless after the review.", score: 0.03, reason: .exact)

        let answer = await EvidenceFridayEngine.answer(question: "Why does work feel hopeless?", evidence: [safe])

        #expect(answer.responseMode == .gentle)
        #expect(!answer.evidence.isEmpty)
    }

    // MARK: Proactive cards and Smart Prompts

    @Test func proactiveAnalysisSkipsHighRiskAndHopelessEntries() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let calm = makeEntry("Lunch with Maya by the lake.", in: context)
        let stressed = makeEntry("Work left me overwhelmed again.", in: context)
        let hopeless = makeEntry("Everything feels hopeless lately.", in: context)
        let risky = makeEntry("I keep thinking about ending my life.", in: context)

        let ids = Set(ProactiveReflectionController.analyzableSnapshots([calm, stressed, hopeless, risky]).map(\.id))

        #expect(ids.contains(try #require(calm.id)))
        #expect(ids.contains(try #require(stressed.id)))
        #expect(!ids.contains(try #require(hopeless.id)))
        #expect(!ids.contains(try #require(risky.id)))
    }

    // MARK: Weekly Reflection

    @Test func weeklyFilterCatchesIndirectWording() {
        let snapshot = WeeklyReflectionEntrySnapshot(
            id: UUID(),
            date: Date(),
            updatedAt: Date(),
            mood: Mood.sad.rawValue,
            text: "Some nights I think everyone would be better off without me.",
            sourceType: .text
        )

        #expect(WeeklyReflectionSafetyFilter.isHighRisk(snapshot))
        #expect(WeeklyReflectionSafetyFilter.safetyLevel(for: [snapshot]) == .highRiskExcluded)
    }

    // MARK: Get Support

    @Test func crisisResourcesCoverListedRegionsAndFallBack() throws {
        let us = CrisisResources.resources(for: "US")
        #expect(us.emergencyNumber == "911")
        let lifeline = try #require(us.helplines.first)
        #expect(lifeline.callNumber == "988")
        #expect(lifeline.textNumber == "988")

        #expect(CrisisResources.resources(for: "gb").helplines.first?.callNumber == "116123")
        #expect(CrisisResources.resources(for: "ZZ") == CrisisResources.fallback)
        #expect(CrisisResources.resources(for: nil).helplines.isEmpty)

        for (region, resources) in CrisisResources.byRegion {
            #expect(!resources.helplines.isEmpty, "\(region)")
            for helpline in resources.helplines {
                #expect(helpline.callNumber != nil || helpline.textNumber != nil, "\(helpline.id)")
                for number in [helpline.callNumber, helpline.textNumber].compactMap({ $0 }) {
                    let isDigitsOnly = number.allSatisfy { $0.isNumber }
                    #expect(isDigitsOnly, "\(helpline.id): \(number)")
                }
            }
        }
    }

    // MARK: Helpers

    private func evidence(
        _ id: String,
        _ text: String,
        score: Double,
        reason: EvidenceReference.MatchReason = .meaning
    ) -> EvidenceReference {
        EvidenceReference(
            id: id,
            entryID: UUID(),
            date: Date(),
            mood: nil,
            snippet: text,
            chunkText: text,
            score: score,
            matchReason: reason
        )
    }

    private func makeEntry(_ text: String, in context: NSManagedObjectContext) -> DiaryEntry {
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = Date()
        entry.createdAt = Date()
        entry.updatedAt = Date()
        entry.text = text
        return entry
    }
}
