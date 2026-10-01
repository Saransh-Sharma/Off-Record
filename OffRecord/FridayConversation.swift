//
//  FridayConversation.swift
//  OffRecord
//
//  Friday's chat, phrased by Apple's on-device model across turns. One
//  model session lives for the whole chat (a window of recent turns is kept
//  when it grows) and is dropped on New Chat. The model looks things up with
//  three journal tools (FridayConversationTools.swift) and must cite only
//  entry IDs those tools returned.
//
//  The safety gates run before and after the model, never inside it:
//  1. A high-risk question gets support copy; the model never sees it.
//  2. The question's own search runs deterministically first, so "every
//     strong match is high-risk" still ends in support copy.
//  3. Tools drop high-risk passages, and a turn whose tools hit only
//     high-risk content ends in support copy.
//  4. The answer passes FridayAnswerValidator (Voice, clinical terms, Weekly
//     forbidden phrases, invented names) and cites only tool-returned IDs.
//  Anything else falls back to EvidenceFridayEngine, unchanged.
//
//  Answers aren't streamed: citations and wording are checked on the whole
//  answer, and showing text that may then be withdrawn is worse than a short
//  wait. The existing sentence-by-sentence reveal shows the checked answer.
//

import Foundation
import JournalFoundation
import KnowledgeGraphKit
import SemanticMemoryKit
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

private let conversationLogger = Logger(subsystem: "com.singularity.offrecord", category: "FridayConversation")

// MARK: - Responder seam

/// The model's answer before validation.
struct FridayConversationDraft: Equatable, Sendable {
    struct Observation: Equatable, Sendable {
        let text: String
        let evidenceIDs: [String]
    }

    let summary: String
    let observations: [Observation]
    let limitations: String?
}

/// A multi-turn, tool-calling model. The engine owns the gates; this only talks to the model.
@MainActor
protocol FridayConversationResponding: AnyObject {
    var isAvailable: Bool { get }
    /// Loads the model ahead of the first question.
    func prewarm()
    /// Forgets the conversation (New Chat).
    func reset()
    /// Answers one turn, calling tools through `tools`. Nil means "no answer", not an error.
    func respond(to question: String, tools: FridayToolRunner) async throws -> FridayConversationDraft?
    /// Adds a turn the person saw but the model didn't write (a fallback or a
    /// suggested question), so the next turn has context.
    func recordShownTurn(question: String, answer: String)
    /// Drops the last turn from the model's memory (its answer was rejected).
    func discardLastTurn()
}

/// Runs the journal tools for one turn against a fixed snapshot.
struct FridayToolRunner: Sendable {
    let context: FridayJournalToolContext
    let ledger: FridayToolLedger

    func searchJournal(query: String) async -> String {
        await FridayJournalTools.searchJournal(query: query, context: context, ledger: ledger)
    }

    func moodStats(startDate: String?, endDate: String?) -> String {
        FridayJournalTools.moodStats(startDate: startDate, endDate: endDate, context: context, ledger: ledger)
    }

    func person(name: String) async -> String {
        await FridayJournalTools.person(name: name, context: context, ledger: ledger)
    }
}

// MARK: - Engine

@MainActor
final class FridayConversationEngine {
    static let shared = FridayConversationEngine()

    typealias Retrieve = (String, [IndexableEntry]) async -> SemanticMemorySearchResult
    typealias EntriesFallback = (String, [DiaryEntry], String?) async -> EvidenceBackedFridayAnswer
    typealias EvidenceFallback = (String, [EvidenceReference]) async -> EvidenceBackedFridayAnswer

    private let responder: (any FridayConversationResponding)?
    private let isModelAllowed: () -> Bool
    private let retrieve: Retrieve
    private let entriesFallback: EntriesFallback
    private let evidenceFallback: EvidenceFallback
    let ledger = FridayToolLedger()

    /// The defaults are the live app; tests pass a scripted model and fixed search.
    init(
        responder: (any FridayConversationResponding)? = FridayConversationEngine.systemResponder(),
        isModelAllowed: @escaping () -> Bool = { FridayLanguageModel.isAvailable },
        retrieve: @escaping Retrieve = { query, records in
            await SemanticMemoryIndexController.shared.search(query: query, records: records, limit: 6)
        },
        entriesFallback: @escaping EntriesFallback = { question, entries, profileSummary in
            await EvidenceFridayEngine.answer(question: question, entries: entries, profileSummary: profileSummary)
        },
        evidenceFallback: @escaping EvidenceFallback = { question, evidence in
            await EvidenceFridayEngine.answer(question: question, evidence: evidence)
        }
    ) {
        self.responder = responder
        self.isModelAllowed = isModelAllowed
        self.retrieve = retrieve
        self.entriesFallback = entriesFallback
        self.evidenceFallback = evidenceFallback
    }

    var usesModel: Bool {
        guard let responder else { return false }
        return isModelAllowed() && responder.isAvailable
    }

    func prewarm() {
        guard usesModel else { return }
        responder?.prewarm()
    }

    /// New Chat: the model forgets the conversation.
    func reset() {
        responder?.reset()
        ledger.reset()
    }

    /// One chat turn. Suggested questions (with a profile summary) and every
    /// gate's fallback go through `EvidenceFridayEngine`, unchanged.
    func answer(question: String, entries: [DiaryEntry], profileSummary: String?) async -> EvidenceBackedFridayAnswer {
        // 1. The model never sees a high-risk question.
        if JournalRiskClassifier.responseMode(for: question) == .supportOnly {
            return .supportOnly(persona: .friday)
        }
        let permitted = entries.filter(FridayEntryIntelligence.permitsAssistantEvidence)
        guard profileSummary == nil, usesModel, let responder else {
            let answer = await entriesFallback(question, permitted, profileSummary)
            remember(question: question, answer: answer)
            return answer
        }

        // 2. The question's own search, with the deterministic high-risk rule.
        let records = SemanticMemoryIndexController.records(from: permitted)
        guard case .ready(let retrieved) = await retrieve(question, records) else {
            // Building, unavailable, or failed: the deterministic path waits or explains.
            let answer = await entriesFallback(question, permitted, nil)
            remember(question: question, answer: answer)
            return answer
        }
        let permittedIDs = Set(records.map(\.id))
        let evidence = retrieved.filter { permittedIDs.contains($0.entryID) }
        let baseline = EvidenceFridayEngine.deterministicAnswer(question: question, evidence: evidence)
        if baseline.answer.responseMode == .supportOnly {
            return baseline.answer
        }

        // 3. The model, with tools over a snapshot.
        let context = toolContext(records)
        let validated = await modelAnswer(question: question, context: context, responder: responder)
        if let validated {
            return validated
        }
        if ledger.withheldHighRisk {
            return .supportOnly(persona: .friday)
        }
        let fallback = await evidenceFallback(question, evidence)
        remember(question: question, answer: fallback)
        return fallback
    }

    /// Runs one model turn and returns it only if every check passes.
    func modelAnswer(
        question: String,
        context: FridayJournalToolContext,
        responder: any FridayConversationResponding
    ) async -> EvidenceBackedFridayAnswer? {
        ledger.beginTurn()
        let draft: FridayConversationDraft?
        do {
            draft = try await responder.respond(to: question, tools: FridayToolRunner(context: context, ledger: ledger))
        } catch {
            conversationLogger.notice("Friday's model turn failed; using the deterministic answer.")
            responder.discardLastTurn()
            return nil
        }
        // A tool reached high-risk content: no model wording survives this turn.
        guard !ledger.withheldHighRisk, let draft,
              let answer = Self.validatedAnswer(draft, question: question, ledger: ledger) else {
            responder.discardLastTurn()
            return nil
        }
        conversationLogger.notice("Friday answered with the model and \(self.ledger.toolCalls.count, privacy: .public) tool calls.")
        return answer
    }

    /// The draft as an answer, or nil when a cited ID wasn't returned by a tool,
    /// nothing is cited, or any wording fails the checks.
    static func validatedAnswer(_ draft: FridayConversationDraft, question: String, ledger: FridayToolLedger) -> EvidenceBackedFridayAnswer? {
        let returnedIDs = ledger.evidenceIDs
        let observations = draft.observations.filter { !$0.evidenceIDs.isEmpty }
        let cited = observations.flatMap(\.evidenceIDs)
        // Every claim cites, and every citation is real.
        guard !cited.isEmpty, cited.allSatisfy(returnedIDs.contains),
              draft.observations.allSatisfy({ $0.evidenceIDs.allSatisfy(returnedIDs.contains) }) else { return nil }

        var orderedIDs: [String] = []
        for id in cited where !orderedIDs.contains(id) { orderedIDs.append(id) }
        let evidence = ledger.evidence(for: orderedIDs)
        let questionMode = JournalRiskClassifier.responseMode(for: question)
        let confidence = min(0.9, 0.35 + Double(Set(evidence.map(\.entryID)).count) * 0.11)
        let candidate = EvidenceBackedFridayAnswer(
            summary: draft.summary,
            observations: observations.map { EvidenceObservation(text: $0.text, evidenceIDs: $0.evidenceIDs) },
            evidence: evidence,
            confidence: confidence,
            followUpPrompt: nil,
            limitations: draft.limitations,
            responseMode: questionMode
        )
        return FridayAnswerValidator.validated(candidate, question: question, evidence: evidence)?
            .withResponseMode(questionMode)
    }

    private func remember(question: String, answer: EvidenceBackedFridayAnswer) {
        guard usesModel, answer.responseMode != .supportOnly else { return }
        responder?.recordShownTurn(question: question, answer: answer.summary)
    }

    /// Tools read this snapshot; tests replace it.
    var toolContext: ([IndexableEntry]) -> FridayJournalToolContext = FridayConversationEngine.liveToolContext(records:)

    static func liveToolContext(records: [IndexableEntry]) -> FridayJournalToolContext {
        let preferences = FridayMemoryPreferences.shared
        return FridayJournalToolContext(
            records: records,
            graph: FridayAssistantEngine.shared.knowledgeGraph,
            forgottenIDs: preferences.forgottenIDs,
            aliases: preferences.aliases,
            now: Date(),
            calendar: .current,
            search: { query in
                await SemanticMemoryIndexController.shared.search(query: query, records: records, limit: 8)
            },
            strongEvidence: { evidence in
                await MainActor.run { EvidenceFridayEngine.strongEvidence(from: evidence) }
            }
        )
    }

    nonisolated static func systemResponder() -> (any FridayConversationResponding)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return FoundationModelsFridayConversationResponder()
        }
        #endif
        return nil
    }
}

// MARK: - Foundation Models

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedFridayChatObservation {
    @Guide(description: "One short sentence about what the cited entries show.")
    let text: String
    @Guide(description: "IDs of the entries that support the sentence, copied exactly from tool results.")
    let evidenceIDs: [String]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedFridayChatAnswer {
    @Guide(description: "The answer in at most 2 short sentences.")
    let summary: String
    @Guide(description: "Findings from the tool results, each one sentence with its evidence IDs.", .maximumCount(3))
    let observations: [GeneratedFridayChatObservation]
    @Guide(description: "At most 1 sentence about what the entries can’t show. Omit when there is nothing to add.")
    let limitations: String?
}

/// Holds the current turn's tool runner so the session's tools, created once,
/// read this turn's snapshot.
final class FridayToolRunnerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var runner: FridayToolRunner?

    var current: FridayToolRunner? { lock.withLock { runner } }
    func set(_ value: FridayToolRunner?) { lock.withLock { runner = value } }
}

@available(iOS 26.0, *)
struct SearchJournalTool: Tool {
    let name = FridayJournalTools.searchToolName
    let description = "Searches the person’s journal. Returns entry IDs, dates, moods, and short excerpts."

    @Generable
    struct Arguments {
        @Guide(description: "Words to search for: a name, topic, place, feeling, or event.")
        let query: String
    }

    let box: FridayToolRunnerBox

    func call(arguments: Arguments) async throws -> String {
        guard let runner = box.current else { return "Search isn’t available." }
        return await runner.searchJournal(query: arguments.query)
    }
}

@available(iOS 26.0, *)
struct MoodStatsTool: Tool {
    let name = FridayJournalTools.moodToolName
    let description = "Counts the moods the person tagged between two dates. Returns counts and example entry IDs."

    @Generable
    struct Arguments {
        @Guide(description: "First day to count, as yyyy-MM-dd.")
        let startDate: String
        @Guide(description: "Last day to count, as yyyy-MM-dd.")
        let endDate: String
    }

    let box: FridayToolRunnerBox

    func call(arguments: Arguments) async throws -> String {
        guard let runner = box.current else { return "Mood counts aren’t available." }
        return runner.moodStats(startDate: arguments.startDate, endDate: arguments.endDate)
    }
}

@available(iOS 26.0, *)
struct PersonTool: Tool {
    let name = FridayJournalTools.personToolName
    let description = "Looks up what the journal says about a person or place by name. Returns facts and entry IDs."

    @Generable
    struct Arguments {
        @Guide(description: "The name as the person wrote it.")
        let name: String
    }

    let box: FridayToolRunnerBox

    func call(arguments: Arguments) async throws -> String {
        guard let runner = box.current else { return "Nothing remembered." }
        return await runner.person(name: arguments.name)
    }
}

@available(iOS 26.0, *)
@MainActor
final class FoundationModelsFridayConversationResponder: FridayConversationResponding {
    /// Past this many turns, the session restarts with only the latest few.
    static let maximumTurns = 6
    static let keptTurns = 3

    static let instructions = """
    You are Friday, the companion in a private journal app. You answer questions about the person’s own journal.
    Rules:
    - Call searchJournal, moodStats, or person to find entries before you answer. Answer only from what the tools return.
    - Every observation cites the entry IDs it is based on, copied exactly from tool results. Never cite an ID a tool didn’t return.
    - If the tools find nothing, say you don’t have enough entries on that.
    - Never invent people, events, dates, moods, or causes.
    - Speak to the person as you. Say I only about your own limits. Never say I noticed.
    - Use 1 to 3 short sentences in plain words. Lead with what the entries show, with dates or counts. Explanations start with Based on.
    - No exclamation marks, emoji, quotation marks, em dashes, advice, or praise.
    - Never use these words: gentle, journey, safe space, valid, brave, self-care, just, simply, actually, unlock, thread.
    - Never use clinical or diagnostic language.
    """

    private let box = FridayToolRunnerBox()
    private var session: LanguageModelSession?
    private var transcriptBeforeTurn: Transcript?
    private var turns = 0

    /// Nothing is loaded until the chat opens (`prewarm`) or a question arrives.
    nonisolated init() {}

    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func prewarm() {
        makeSessionIfNeeded().prewarm()
    }

    func reset() {
        session = nil
        transcriptBeforeTurn = nil
        turns = 0
    }

    func respond(to question: String, tools: FridayToolRunner) async throws -> FridayConversationDraft? {
        guard isAvailable else { return nil }
        box.set(tools)
        defer { box.set(nil) }

        let session = makeSessionIfNeeded()
        transcriptBeforeTurn = session.transcript
        let prompt = Self.prompt(for: question, now: tools.context.now, calendar: tools.context.calendar)
        let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: 420)
        let content: GeneratedFridayChatAnswer
        do {
            content = try await session.respond(to: prompt, generating: GeneratedFridayChatAnswer.self, options: options).content
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize(_) {
            // Start over with only the rules, then try once more.
            rebuild(keepingTurns: 0, from: session.transcript)
            guard let fresh = self.session else { return nil }
            transcriptBeforeTurn = fresh.transcript
            content = try await fresh.respond(to: prompt, generating: GeneratedFridayChatAnswer.self, options: options).content
        }
        turns += 1
        if turns > Self.maximumTurns, let current = self.session {
            rebuild(keepingTurns: Self.keptTurns, from: current.transcript)
        }
        return FridayConversationDraft(
            summary: content.summary,
            observations: content.observations.map { .init(text: $0.text, evidenceIDs: $0.evidenceIDs) },
            limitations: content.limitations
        )
    }

    func recordShownTurn(question: String, answer: String) {
        guard isAvailable else { return }
        let session = makeSessionIfNeeded()
        let entries = Array(session.transcript) + [
            .prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: question))])),
            .response(Transcript.Response(assetIDs: [], segments: [.text(Transcript.TextSegment(content: answer))])),
        ]
        self.session = makeSession(transcript: Transcript(entries: entries))
        turns += 1
    }

    func discardLastTurn() {
        guard let transcriptBeforeTurn else { return }
        session = makeSession(transcript: transcriptBeforeTurn)
        self.transcriptBeforeTurn = nil
    }

    // MARK: Session

    private var tools: [any Tool] {
        [SearchJournalTool(box: box), MoodStatsTool(box: box), PersonTool(box: box)]
    }

    private func makeSessionIfNeeded() -> LanguageModelSession {
        if let session { return session }
        let created = LanguageModelSession(model: .default, tools: tools, instructions: Self.instructions)
        session = created
        return created
    }

    private func makeSession(transcript: Transcript) -> LanguageModelSession {
        LanguageModelSession(model: .default, tools: tools, transcript: transcript)
    }

    /// Keeps the rules and the last `keepingTurns` question-and-answer pairs,
    /// dropping tool calls and their output.
    private func rebuild(keepingTurns: Int, from transcript: Transcript) {
        session = makeSession(transcript: Self.windowed(transcript, keepingTurns: keepingTurns))
        turns = min(turns, keepingTurns)
    }

    static func windowed(_ transcript: Transcript, keepingTurns: Int) -> Transcript {
        var instructions: Transcript.Entry?
        var pairs: [[Transcript.Entry]] = []
        for entry in transcript {
            switch entry {
            case .instructions:
                if instructions == nil { instructions = entry }
            case .prompt:
                pairs.append([entry])
            case .response:
                if !pairs.isEmpty { pairs[pairs.count - 1].append(entry) }
            case .toolCalls, .toolOutput:
                continue
            @unknown default:
                continue
            }
        }
        let kept = keepingTurns > 0 ? pairs.suffix(keepingTurns).flatMap { $0 } : []
        return Transcript(entries: (instructions.map { [$0] } ?? []) + kept)
    }

    static func prompt(for question: String, now: Date, calendar: Calendar) -> String {
        """
        Today is \(FridayJournalTools.dayString(now, calendar: calendar)).
        Question: \(question)
        Use the tools, then answer. Cite only entry IDs the tools returned.
        """
    }
}
#endif
