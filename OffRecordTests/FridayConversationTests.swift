import CoreData
import Foundation
import JournalFoundation
import KnowledgeGraphKit
import Testing
@testable import OffRecord
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Friday's multi-turn chat: the gates around the model, the journal tools,
/// and citation checks against what the tools actually returned. A scripted
/// responder plays the model.
@MainActor
@Suite(.serialized)
struct FridayConversationTests {
    private let mayaID = UUID()
    private let workID = UUID()
    private let riskyID = UUID()
    private let hiddenID = UUID()
    private let context = PersistenceController(inMemory: true).container.viewContext

    // MARK: Gates

    @Test func highRiskQuestionNeverReachesTheModel() async {
        let responder = ScriptedResponder { _, _ in Self.draft(citing: ["anything"]) }
        let engine = makeEngine(responder: responder, retrieve: { _, _ in
            Issue.record("A high-risk question must not be searched.")
            return .ready([])
        })

        let answer = await engine.answer(question: "Why do I want to hurt myself?", entries: entries(), profileSummary: nil)

        #expect(answer.responseMode == .supportOnly)
        #expect(answer.summary == FridayPersonality.riskSafeSupport)
        #expect(answer.evidence.isEmpty)
        #expect(responder.respondCalls == 0)
        #expect(responder.shownTurns.isEmpty)
    }

    @Test func questionWhoseStrongMatchesAreAllHighRiskGetsSupportWithoutTheModel() async {
        let responder = ScriptedResponder { _, _ in Self.draft(citing: ["risky"]) }
        let risky = evidence("risky", riskyID, "Everyone would be better off without me after the meeting.", score: 0.05)
        let engine = makeEngine(responder: responder, retrieve: { _, _ in .ready([risky]) })

        let answer = await engine.answer(question: "How was last week?", entries: entries(), profileSummary: nil)

        #expect(answer.responseMode == .supportOnly)
        #expect(responder.respondCalls == 0)
    }

    @Test func toolThatHitsOnlyHighRiskContentEndsTheTurnInSupport() async {
        let safe = evidence("work", workID, "Work pressure was heavy after the meeting.", score: 0.03)
        let risky = evidence("risky", riskyID, "After the meeting I thought about suicide.", score: 0.05)
        // The question's own search is safe; the model's follow-up search only finds the risky entry.
        let responder = ScriptedResponder { _, tools in
            _ = await tools.searchJournal(query: "the night after the meeting")
            return Self.draft(citing: ["work"])
        }
        let engine = makeEngine(responder: responder, retrieve: { query, _ in
            query == "work pressure" ? .ready([safe]) : .ready([risky])
        }, toolSearch: { _ in .ready([risky]) })

        let answer = await engine.answer(question: "work pressure", entries: entries(), profileSummary: nil)

        #expect(responder.respondCalls == 1)
        #expect(answer.responseMode == .supportOnly)
        #expect(answer.evidence.isEmpty)
        #expect(responder.discardedTurns == 1)
    }

    @Test func suggestedQuestionsStayDeterministic() async {
        let responder = ScriptedResponder { _, _ in Self.draft(citing: ["work"]) }
        let engine = makeEngine(responder: responder, retrieve: { _, _ in .ready([]) })
        let profile = "Your recent mood has been good."

        let answer = await engine.answer(question: "How’s my mood this week?", entries: entries(), profileSummary: profile)

        #expect(responder.respondCalls == 0)
        #expect(answer.summary == profile)
        // The model still learns what was said, for the next turn.
        #expect(responder.shownTurns.count == 1)
    }

    @Test func unavailableModelFallsBackWithoutCallingIt() async {
        let responder = ScriptedResponder(isAvailable: false) { _, _ in Self.draft(citing: ["work"]) }
        let engine = makeEngine(responder: responder, retrieve: { _, _ in .ready([]) })
        engine.prewarm()

        let answer = await engine.answer(question: "What stresses me out?", entries: entries(), profileSummary: nil)

        #expect(!engine.usesModel)
        #expect(responder.prewarmCalls == 0)
        #expect(responder.respondCalls == 0)
        #expect(responder.shownTurns.isEmpty)
        #expect(answer.summary.contains("not have enough journal evidence"))
    }

    // MARK: Citations

    @Test func answerCitingToolResultsIsKept() async {
        let work = evidence("work", workID, "Work pressure was heavy after the meeting with Maya.", score: 0.03)
        let responder = ScriptedResponder { _, tools in
            _ = await tools.searchJournal(query: "work pressure")
            return FridayConversationDraft(
                summary: "Work pressure shows up after meetings.",
                observations: [.init(text: "One entry ties it to a meeting with Maya.", evidenceIDs: ["work"])],
                limitations: nil
            )
        }
        let engine = makeEngine(responder: responder, retrieve: { _, _ in .ready([work]) }, toolSearch: { _ in .ready([work]) })

        let answer = await engine.answer(question: "What did I write about work pressure?", entries: entries(), profileSummary: nil)

        #expect(answer.summary == "Work pressure shows up after meetings.")
        #expect(answer.evidence.map(\.id) == ["work"])
        #expect(answer.observations.allSatisfy { $0.evidenceIDs == ["work"] })
        #expect(answer.responseMode == .normal)
        #expect(answer.followUpPrompt == nil)
        #expect(responder.discardedTurns == 0)
    }

    @Test func answerCitingAnIDNoToolReturnedFallsBack() async {
        let work = evidence("work", workID, "Work pressure was heavy after the meeting.", score: 0.03)
        let responder = ScriptedResponder { _, tools in
            _ = await tools.searchJournal(query: "work pressure")
            return Self.draft(citing: ["work", "made-up"])
        }
        let engine = makeEngine(responder: responder, retrieve: { _, _ in .ready([work]) }, toolSearch: { _ in .ready([work]) })

        let answer = await engine.answer(question: "work pressure", entries: entries(), profileSummary: nil)

        #expect(answer.summary != Self.draft(citing: []).summary)
        #expect(!answer.evidence.contains { $0.id == "made-up" })
        #expect(answer.observations.allSatisfy { !$0.evidenceIDs.contains("made-up") })
        #expect(responder.discardedTurns == 1)
        // The fallback is recorded so the next turn knows what was shown.
        #expect(responder.shownTurns.count == 1)
    }

    @Test func answerWithoutToolCallsOrCitationsFallsBack() async {
        let ledger = FridayToolLedger()
        #expect(FridayConversationEngine.validatedAnswer(Self.draft(citing: ["work"]), question: "work", ledger: ledger) == nil)

        ledger.record([evidence("work", workID, "Work pressure was heavy.", score: 0.03)])
        #expect(FridayConversationEngine.validatedAnswer(Self.draft(citing: []), question: "work", ledger: ledger) == nil)
        #expect(FridayConversationEngine.validatedAnswer(Self.draft(citing: ["work"]), question: "work", ledger: ledger) != nil)

        let offVoice = FridayConversationDraft(
            summary: "I noticed work is a journey for you.",
            observations: [.init(text: "Work came up once.", evidenceIDs: ["work"])],
            limitations: nil
        )
        #expect(FridayConversationEngine.validatedAnswer(offVoice, question: "work", ledger: ledger) == nil)
    }

    @Test func gentleQuestionsKeepTheirModeThroughTheModel() {
        let ledger = FridayToolLedger()
        ledger.record([evidence("work", workID, "Work felt hopeless after the review.", score: 0.03)])
        let draft = FridayConversationDraft(
            summary: "Work felt hopeless after the review in 1 entry.",
            observations: [.init(text: "It came up after a review.", evidenceIDs: ["work"])],
            limitations: nil
        )
        let answer = FridayConversationEngine.validatedAnswer(draft, question: "Why does work feel hopeless?", ledger: ledger)
        #expect(answer?.responseMode == .gentle)
    }

    // MARK: Tools

    @Test func searchToolDropsHighRiskAndExcludedEntries() async {
        let ledger = FridayToolLedger()
        let results: [EvidenceReference] = [
            evidence("maya", mayaID, "Lunch with Maya by the lake.", score: 0.04),
            evidence("risky", riskyID, "I keep thinking about ending my life.", score: 0.03),
            evidence("hidden", hiddenID, "Lunch with Maya again, kept out of Friday.", score: 0.05),
        ]
        let context = toolContext(search: { _ in .ready(results) })

        let output = await FridayJournalTools.searchJournal(query: "Maya", context: context, ledger: ledger)

        #expect(output.contains("id: maya"))
        #expect(!output.contains("risky"))
        #expect(!output.contains("ending my life"))
        #expect(!output.contains("hidden"))
        #expect(ledger.evidenceIDs == ["maya"])
        #expect(!ledger.withheldHighRisk)
    }

    @Test func searchToolNeverRunsAHighRiskQuery() async {
        let ledger = FridayToolLedger()
        let context = toolContext(search: { _ in
            Issue.record("A high-risk tool query must not be searched.")
            return .ready([])
        })

        let output = await FridayJournalTools.searchJournal(query: "times I wanted to kill myself", context: context, ledger: ledger)

        #expect(ledger.withheldHighRisk)
        #expect(ledger.evidenceIDs.isEmpty)
        #expect(!output.contains("kill"))
    }

    @Test func moodStatsCountsMoodsWithoutTextOrHighRiskEntries() {
        let ledger = FridayToolLedger()
        let context = toolContext()

        let output = FridayJournalTools.moodStats(startDate: "2026-09-01", endDate: "2026-09-30", context: context, ledger: ledger)

        #expect(output.hasPrefix("2 entries from 2026-09-01 to 2026-09-30"))
        #expect(output.contains("calm: 1"))
        #expect(output.contains("anxious: 1"))
        #expect(!output.contains("lake"))
        #expect(!output.contains("sad"))
        #expect(ledger.evidenceIDs == ["mood-\(mayaID.uuidString)", "mood-\(workID.uuidString)"])
        #expect(FridayJournalTools.moodStats(startDate: "2025-01-01", endDate: "2025-01-31", context: context, ledger: ledger).hasPrefix("No entries"))
    }

    @Test func personToolHonorsForgetAndRename() async {
        let ledger = FridayToolLedger()
        var graph = PersonalKnowledgeGraph()
        graph.addOrUpdate(id: "Maya", label: "Maya", type: .person, sentiment: 0.5)
        graph.addOrUpdate(id: "Maya", label: "Maya", type: .person, sentiment: 0.5)
        graph.addOrUpdate(id: "Arjun", label: "Arjun", type: .person)
        graph.connect("Maya", to: "Lisbon")
        graph.addOrUpdate(id: "Lisbon", label: "Lisbon", type: .place)
        let maya = evidence("maya", mayaID, "Lunch with Maya by the lake.", score: 0.04)
        let context = toolContext(
            graph: graph,
            forgottenIDs: ["arjun"],
            aliases: ["maya": "May"],
            search: { query in query == "Maya" ? .ready([maya]) : .ready([]) }
        )

        let byAlias = await FridayJournalTools.person(name: "May", context: context, ledger: ledger)
        let forgotten = await FridayJournalTools.person(name: "Arjun", context: context, ledger: ledger)

        #expect(byAlias.hasPrefix("May (person): mentioned 2 times"))
        #expect(byAlias.contains("Lisbon"))
        #expect(byAlias.contains("id: maya"))
        #expect(forgotten.hasPrefix("Nothing remembered"))
        #expect(ledger.evidenceIDs == ["maya"])
    }

    // MARK: Transcript window

    @Test func transcriptWindowKeepsRulesAndRecentTurnsOnly() throws {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return }
        var entries: [Transcript.Entry] = [
            .instructions(Transcript.Instructions(segments: [.text(.init(content: "Rules"))], toolDefinitions: []))
        ]
        for turn in 1...4 {
            entries.append(.prompt(Transcript.Prompt(segments: [.text(.init(content: "Question \(turn)"))])))
            entries.append(.toolOutput(Transcript.ToolOutput(id: "t\(turn)", toolName: "searchJournal", segments: [.text(.init(content: "id: e\(turn)"))])))
            entries.append(.response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: "Answer \(turn)"))])))
        }

        let windowed = FoundationModelsFridayConversationResponder.windowed(Transcript(entries: entries), keepingTurns: 2)

        #expect(windowed.count == 5)
        guard case .instructions = windowed[0] else { Issue.record("Rules come first"); return }
        func firstText(_ segments: [Transcript.Segment]) -> String? {
            guard case .text(let segment)? = segments.first else { return nil }
            return segment.content
        }
        let texts = windowed.compactMap { entry -> String? in
            switch entry {
            case .prompt(let prompt): return firstText(prompt.segments)
            case .response(let response): return firstText(response.segments)
            case .toolOutput: return "tool"
            default: return nil
            }
        }
        #expect(texts == ["Question 3", "Answer 3", "Question 4", "Answer 4"])
        #expect(FoundationModelsFridayConversationResponder.windowed(Transcript(entries: entries), keepingTurns: 0).count == 1)
        #endif
    }

    // MARK: Helpers

    static func draft(citing ids: [String]) -> FridayConversationDraft {
        FridayConversationDraft(
            summary: "Work comes up after meetings.",
            observations: [.init(text: "Work pressure came up once.", evidenceIDs: ids)],
            limitations: nil
        )
    }

    private func evidence(_ id: String, _ entryID: UUID, _ text: String, score: Double) -> EvidenceReference {
        EvidenceReference(id: id, entryID: entryID, date: Date(), mood: "anxious", snippet: text, chunkText: text, score: score, matchReason: .exact)
    }

    /// Journal entries matching `records()`, so the engine's permitted-entry filter keeps them.
    private func entries() -> [DiaryEntry] {
        records().map { record in
            let entry = DiaryEntry(context: context)
            entry.id = record.id
            entry.date = record.date
            entry.createdAt = record.date
            entry.updatedAt = record.date
            entry.text = record.text
            entry.setValue(record.mood, forKey: "mood")
            return entry
        }
    }

    private func records() -> [IndexableEntry] {
        let september = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 12))!
        return [
            IndexableEntry(id: mayaID, date: september, mood: "calm", text: "Lunch with Maya by the lake.", isStarred: false),
            IndexableEntry(id: workID, date: september.addingTimeInterval(86_400), mood: "anxious", text: "Work pressure was heavy after the meeting.", isStarred: false),
            IndexableEntry(id: riskyID, date: september.addingTimeInterval(172_800), mood: "sad", text: "I keep thinking about ending my life.", isStarred: false),
        ]
    }

    private func toolContext(
        graph: PersonalKnowledgeGraph = PersonalKnowledgeGraph(),
        forgottenIDs: Set<String> = [],
        aliases: [String: String] = [:],
        search: @escaping FridayJournalToolContext.Search = { _ in .ready([]) }
    ) -> FridayJournalToolContext {
        FridayJournalToolContext(
            records: records(),
            graph: graph,
            forgottenIDs: forgottenIDs,
            aliases: aliases,
            now: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!,
            calendar: .current,
            search: search,
            strongEvidence: { evidence in evidence.filter { $0.score >= 0.012 } }
        )
    }

    private func makeEngine(
        responder: ScriptedResponder,
        retrieve: @escaping FridayConversationEngine.Retrieve,
        toolSearch: @escaping FridayJournalToolContext.Search = { _ in .ready([]) }
    ) -> FridayConversationEngine {
        // Deterministic fallbacks only: no real model and no shared index in unit tests.
        let engine = FridayConversationEngine(
            responder: responder,
            isModelAllowed: { true },
            retrieve: retrieve,
            entriesFallback: { question, _, profileSummary in
                EvidenceFridayEngine.deterministicAnswer(question: question, evidence: [], profileSummary: profileSummary).answer
            },
            evidenceFallback: { question, evidence in
                EvidenceFridayEngine.deterministicAnswer(question: question, evidence: evidence).answer
            }
        )
        engine.toolContext = { [self] _ in toolContext(search: toolSearch) }
        return engine
    }
}

// MARK: - Scripted model

@MainActor
final class ScriptedResponder: FridayConversationResponding {
    typealias Script = (String, FridayToolRunner) async -> FridayConversationDraft?

    let isAvailable: Bool
    private let script: Script
    private(set) var respondCalls = 0
    private(set) var prewarmCalls = 0
    private(set) var discardedTurns = 0
    private(set) var shownTurns: [(question: String, answer: String)] = []

    init(isAvailable: Bool = true, script: @escaping Script) {
        self.isAvailable = isAvailable
        self.script = script
    }

    func prewarm() { prewarmCalls += 1 }
    func reset() { shownTurns = [] }

    func respond(to question: String, tools: FridayToolRunner) async throws -> FridayConversationDraft? {
        respondCalls += 1
        return await script(question, tools)
    }

    func recordShownTurn(question: String, answer: String) {
        shownTurns.append((question, answer))
    }

    func discardLastTurn() { discardedTurns += 1 }
}
