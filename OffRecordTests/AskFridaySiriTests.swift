import Foundation
import JournalFoundation
import SemanticMemoryKit
import Testing
@testable import OffRecord

/// Ask Friday inside Siri: support first, summary only, no entry text, neutral voice.
struct AskFridaySiriTests {

    private func evidence(_ text: String, date: Date = Date(timeIntervalSince1970: 1_780_000_000), entryID: UUID = UUID()) -> EvidenceReference {
        EvidenceReference(id: UUID().uuidString, entryID: entryID, date: date, mood: nil, snippet: text, chunkText: text, score: 0.05, matchReason: .exact)
    }

    private func answer(_ summary: String, evidence: [EvidenceReference] = [], mode: SensitiveResponseMode = .normal) -> EvidenceBackedFridayAnswer {
        EvidenceBackedFridayAnswer(summary: summary, observations: [], evidence: evidence, confidence: 0.7, followUpPrompt: nil, limitations: nil, responseMode: mode)
    }

    // MARK: Decisions

    @Test func emptyQuestionAsksForOne() async {
        let reply = await AskFridaySiri.reply(to: "   ", fridayEnabled: true) { _ in Issue.record("No answer for an empty question"); return .supportOnly(persona: .friday) }
        #expect(reply == .needsQuestion)
    }

    @Test func highRiskQuestionGetsSupportWithoutReadingEntries() async {
        let reply = await AskFridaySiri.reply(to: "Why do I want to hurt myself?", fridayEnabled: true) { _ in
            Issue.record("A high-risk question must not reach retrieval")
            return self.answer("Work came up in 3 entries.")
        }
        #expect(reply == .support(FridayPersonality.riskSafeSupport))
    }

    @Test func highRiskQuestionGetsSupportEvenWithFridayOff() async {
        let reply = await AskFridaySiri.reply(to: "I don't want to be alive", fridayEnabled: false) { _ in self.answer("") }
        #expect(reply == .support(FridayPersonality.riskSafeSupport))
    }

    @Test func fridayOffMeansNoAnswer() async {
        let reply = await AskFridaySiri.reply(to: "What did I write about work?", fridayEnabled: false) { _ in
            Issue.record("Friday is off")
            return self.answer("Work came up.")
        }
        #expect(reply == .fridayOff)
    }

    @Test func supportOnlyAnswerBecomesSupport() async {
        let reply = await AskFridaySiri.reply(to: "work", fridayEnabled: true) { _ in .supportOnly(persona: .friday) }
        #expect(reply == .support(FridayPersonality.riskSafeSupport))
    }

    @Test func safeSummaryIsWhatSiriSays() async {
        let reply = await AskFridaySiri.reply(to: "work", fridayEnabled: true) { _ in
            self.answer("3 entries from May 2 to May 9 mention work.", evidence: [self.evidence("The deadline moved again and I stayed late.")])
        }
        #expect(reply == .answer("3 entries from May 2 to May 9 mention work."))
    }

    @Test func slowAnswerOffersToOpenFriday() async {
        let reply = await AskFridaySiri.reply(to: "work", fridayEnabled: true, timeout: .milliseconds(50)) { _ in
            try? await Task.sleep(for: .seconds(2))
            return self.answer("Late.")
        }
        #expect(reply == .needsMoreTime)
    }

    // MARK: Summary filter

    @Test func summaryQuotingAnEntryFallsBackToMetadata() {
        let entry = evidence("After the quarterly review I felt crushed by work stress and pressure.")
        let quoting = answer("You felt crushed by work stress and pressure after reviews.", evidence: [entry])

        let spoken = AskFridaySiri.spokenSummary(for: quoting)

        #expect(!spoken.localizedCaseInsensitiveContains("crushed"))
        #expect(spoken.contains("1 entry"))
    }

    @Test func quotationMarksFallBackToMetadata() {
        let spoken = AskFridaySiri.spokenSummary(for: answer("You wrote “stay late” twice.", evidence: [evidence("stay late")]))
        #expect(!spoken.contains("stay late"))
    }

    @Test func firstPersonSummaryFallsBackToANeutralLine() {
        #expect(AskFridaySiri.spokenSummary(for: answer("I do not have enough journal evidence to answer that yet.")) == "No entries match that yet.")
        #expect(AskFridaySiri.speaksInFirstPerson("I’m still reading your journal."))
        #expect(AskFridaySiri.speaksInFirstPerson("Let me check my notes."))
        #expect(!AskFridaySiri.speaksInFirstPerson("Work came up in 3 entries this month."))
    }

    @Test func metadataSummaryUsesCountsAndDatesOnly() {
        let shared = UUID()
        let may2 = Date(timeIntervalSince1970: 1_777_723_200)
        let may9 = may2.addingTimeInterval(7 * 86_400)
        let range = AskFridaySiri.metadataSummary(for: [
            evidence("Secret one", date: may2, entryID: shared),
            evidence("Secret two", date: may2, entryID: shared),
            evidence("Secret three", date: may9)
        ])

        #expect(range.hasPrefix("2 entries from"))
        #expect(range.hasSuffix("match."))
        #expect(!range.localizedCaseInsensitiveContains("secret"))
        #expect(AskFridaySiri.metadataSummary(for: [evidence("Secret", date: may2)]).hasSuffix("matches."))
        #expect(AskFridaySiri.metadataSummary(for: []) == "No entries match that yet.")
    }

    @Test func wordRunsMatchAcrossPunctuationAndCase() {
        #expect(AskFridaySiri.sharesWordRun("Maya reminded me, to take a proper lunch!", with: ["maya reminded me to take a proper lunch break"], length: 5))
        #expect(!AskFridaySiri.sharesWordRun("Lunch with Maya came up twice.", with: ["maya reminded me to take a proper lunch break"], length: 5))
        #expect(!AskFridaySiri.sharesWordRun("Short.", with: ["Short."], length: 5))
    }

    // MARK: Routing

    @Test func supportRouteRoundTripsAndSkipsTheLock() {
        let url = OffRecordNavigationRouter.url(for: .support)
        #expect(url?.absoluteString == "offrecord://support")
        #expect(url.flatMap(OffRecordNavigationRouter.route(from:)) == .support)
        #expect(OffRecordRoute.support.isAvailableWithoutUnlocking)
        #expect(!OffRecordRoute.friday(question: nil).isAvailableWithoutUnlocking)
        #expect(!OffRecordRoute.today.isAvailableWithoutUnlocking)
    }

    @MainActor
    @Test func supportRouteOpensTheSheetWhileLocked() {
        let router = OffRecordNavigationRouter.shared
        router.presentsSupport = false

        router.route(.support, canNavigate: false)
        #expect(router.presentsSupport)

        router.presentsSupport = false
    }
}
