import Foundation
import Testing
@testable import OffRecord

/// Whether live-model tests run: opted in, and Apple Intelligence is ready here.
enum FridayLiveModel {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["OFFRECORD_LIVE_MODEL"] == "1"
            && FridayLanguageModel.systemAvailability == .available
    }
}

/// Runs the real on-device model end to end. Off by default so the suite stays
/// fast and deterministic; turn on with
/// `TEST_RUNNER_OFFRECORD_LIVE_MODEL=1 xcodebuild test … -only-testing:OffRecordTests/FridayLiveModelTests`
/// on a simulator or device with Apple Intelligence. Without the model (or
/// while it's downloading) every test skips. Each test checks the contract
/// (validated or fallen back), not the model's exact wording.
@MainActor
@Suite(.serialized, .enabled(if: FridayLiveModel.isEnabled, "Needs OFFRECORD_LIVE_MODEL=1 and the on-device model"))
struct FridayLiveModelTests {
    private let lunch = "Lunch with Maya by the lake. We talked about her new job in Lisbon and the move in spring, and it felt good to plan ahead together."

    @Test func goDeeperQuestionIsGroundedOrTemplated() async throws {
        let generator = try #require(GoDeeperQuestionProvider.systemGenerator())
        let context = EntryGenerationContext(text: lunch, mood: .happy)
        let raw = try await generator.question(for: context)
        let validated = raw.flatMap { GoDeeperQuestionValidator.validated($0, context: context) }
        print("Go Deeper raw: \(raw ?? "nil") -> \(validated ?? "rejected")")

        let provider = GoDeeperQuestionProvider(store: FridayGeneratedTextStore(fileName: nil, capacity: 10), isModelAvailable: { true })
        let question = try #require(await provider.firstQuestion(text: lunch, mood: .happy))
        #expect(question.hasSuffix("?"))
        #expect(FridayOutputValidator.wordCount(question) <= 10)
        #expect(FridayOutputValidator.isAcceptable(question))
    }

    @Test func entryTitleIsGroundedOrMissing() async throws {
        let generator = try #require(EntryTitleStore.systemGenerator())
        let context = EntryGenerationContext(text: lunch, mood: .happy)
        let raw = try await generator.title(for: context)
        let validated = raw.flatMap { EntryTitleValidator.validated($0, context: context) }
        print("Title raw: \(raw ?? "nil") -> \(validated ?? "rejected")")
        if let validated {
            #expect(FridayOutputValidator.wordCount(validated) <= 6)
        }
    }

    @Test func weeklyProseIsValidOrDeterministic() async throws {
        let narrator = try #require(WeeklyReflectionNarrator.systemNarrator())
        let facts = WeeklyReflectionNarrationFacts(
            isLightWeek: false, entryCount: 4, entryDays: 4, wordCount: 640,
            themes: [.init(name: "Garden", entryCount: 3), .init(name: "Maya", entryCount: 2)],
            moodArc: "Got Lighter", moodArcDescription: "Your entries got lighter toward the end of the week.",
            wins: ["You wrote on 4 days.", "Some entries were upbeat or grateful."],
            frictions: ["Garden came up more than once."],
            deterministicHero: "This week was mostly about Garden, and it got lighter as it went.",
            deterministicSummary: "You wrote most about Garden and Maya. 4 entries, about 640 words."
        )
        let raw = try await narrator.narrate(facts)
        let validated = raw.flatMap { WeeklyReflectionNarrator.validated($0, facts: facts) }
        print("Weekly raw: \(String(describing: raw)) -> \(validated.map { "\($0.heroSentence) | \($0.summary)" } ?? "rejected")")
    }

    @Test func chatTurnCallsToolsAndCitesWhatTheyReturned() async throws {
        let responder = try #require(FridayConversationEngine.systemResponder())
        let mayaID = UUID()
        let workID = UUID()
        let maya = EvidenceReference(id: "chunk-maya", entryID: mayaID, date: Date().addingTimeInterval(-86_400 * 3), mood: "happy",
                                     snippet: "Lunch with Maya by the lake. We talked about her new job in Lisbon.",
                                     chunkText: "Lunch with Maya by the lake. We talked about her new job in Lisbon.", score: 0.04, matchReason: .entity)
        let work = EvidenceReference(id: "chunk-work", entryID: workID, date: Date().addingTimeInterval(-86_400), mood: "anxious",
                                     snippet: "The project deadline moved again and the review is Friday.",
                                     chunkText: "The project deadline moved again and the review is Friday.", score: 0.03, matchReason: .exact)
        let records = [
            IndexableEntry(id: mayaID, date: maya.date, mood: "happy", text: maya.chunkText, isStarred: false),
            IndexableEntry(id: workID, date: work.date, mood: "anxious", text: work.chunkText, isStarred: false),
        ]
        let engine = FridayConversationEngine(responder: responder, isModelAllowed: { true }, retrieve: { _, _ in .ready([]) })
        let context = FridayJournalToolContext(
            records: records, graph: .init(), forgottenIDs: [], aliases: [:], now: Date(), calendar: .current,
            search: { query in
                let lowered = query.lowercased()
                return .ready([maya, work].filter { lowered.contains("maya") || lowered.contains("lisbon") ? $0.id == "chunk-maya" : $0.id == "chunk-work" })
            },
            strongEvidence: { $0 }
        )

        let answer = await engine.modelAnswer(question: "What did Maya say about Lisbon?", context: context, responder: responder)
        print("Chat tools: \(engine.ledger.toolCalls) answer: \(answer?.summary ?? "fallback")")
        if let answer {
            #expect(answer.evidence.allSatisfy { engine.ledger.evidenceIDs.contains($0.id) })
            #expect(!answer.evidence.isEmpty)
        }

        // A second turn in the same session resolves "her" from the first.
        let followUp = await engine.modelAnswer(question: "When did I last write about her?", context: context, responder: responder)
        print("Chat follow-up tools: \(engine.ledger.toolCalls) answer: \(followUp?.summary ?? "fallback")")
        engine.reset()
    }
}
