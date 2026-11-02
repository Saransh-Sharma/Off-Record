import Foundation
import Testing
@testable import AssistantCoreKit
import JournalFoundation
import SemanticMemoryKit
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(Evaluations)
@_weakLinked import Evaluations
#endif

/// Whether this Mac or device can run Apple's on-device model right now.
/// Only `SystemLanguageModel` is ever used; never a cloud model.
enum OnDeviceModel {
    static var isReady: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }
}

private let livePersona = AssistantPersona(
    id: "friday",
    name: "Friday",
    hostAppName: "OffRecord",
    evidenceSystemPromptTemplate: "You are {name} inside a private journal app. Answer only from the provided evidence.",
    copy: PersonaCopyCatalog(
        welcome: "I’m Friday.",
        insufficientData: "I don’t have enough to go on yet.",
        noticedPrefix: "",
        watchingSuffix: "",
        exclusionRespected: "I don’t have anything on that.",
        riskSafeSupport: "That sounds heavy. Talking to someone you trust could help."
    )
)

/// A small fixed journal for live runs.
enum LiveEvidenceFixtures {
    static let evidence: [EvidenceReference] = [
        reference("maya", "Lunch with Maya by the lake. We talked about her new job in Lisbon.", mood: "happy", daysAgo: 6),
        reference("deadline", "The project deadline moved again and the review is on Friday.", mood: "anxious", daysAgo: 3),
        reference("walk", "A long walk after work helped me settle before the review.", mood: "calm", daysAgo: 2),
    ]

    static let questions = [
        "What did I write about Maya?",
        "How did I feel about the review?",
        "What helped me settle this week?",
    ]

    static func reference(_ id: String, _ text: String, mood: String, daysAgo: Double) -> EvidenceReference {
        EvidenceReference(
            id: id,
            entryID: UUID(),
            date: Date(timeIntervalSince1970: 1_790_000_000 - daysAgo * 86_400),
            mood: mood,
            snippet: text,
            chunkText: text,
            score: 0.03,
            matchReason: .exact
        )
    }
}

/// Runs the shared responder against the real on-device model. Skips cleanly
/// when Apple Intelligence isn't available (or is still downloading).
@Suite(.serialized, .enabled(if: OnDeviceModel.isReady, "Needs the on-device model (Apple Intelligence)"))
struct FoundationModelsEvidenceResponderLiveTests {

    @Test func answersCiteOnlyTheEvidenceTheyWereGiven() async throws {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let allowed = Set(LiveEvidenceFixtures.evidence.map(\.id))
        for question in LiveEvidenceFixtures.questions {
            let fallback = DeterministicEvidenceAnswerBuilder.answer(question: question, evidence: LiveEvidenceFixtures.evidence, persona: livePersona)
            let answer = try await FoundationModelsEvidenceResponder().respond(
                question: question,
                evidence: LiveEvidenceFixtures.evidence,
                persona: livePersona,
                fallback: fallback
            )
            // Nil is a valid outcome (the caller falls back); anything returned must cite real evidence.
            guard let answer else { continue }
            #expect(!answer.evidence.isEmpty)
            #expect(answer.evidence.allSatisfy { allowed.contains($0.id) })
            #expect(answer.observations.allSatisfy { !$0.evidenceIDs.isEmpty && $0.evidenceIDs.allSatisfy(allowed.contains) })
            #expect(answer.confidence <= fallback.confidence)
        }
        #endif
    }

    @Test func evidenceEvaluationKeepsEveryCitationReal() async throws {
        #if canImport(Evaluations)
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let result = try await EvidenceCitationEvaluation().run()
        print(result.groupedSummary)
        #expect(result.aggregateValue(.mean(of: EvidenceCitationEvaluation.citationsAreReal)) == 1)
        #endif
    }
}

#if canImport(Evaluations)
/// Apple's Evaluations framework over the shared evidence responder: every
/// citation must point at given evidence (deterministic), and an on-device
/// judge scores whether the answer says only what the evidence says.
@available(macOS 27.0, iOS 27.0, *)
struct EvidenceCitationEvaluation: Evaluation {
    static let citationsAreReal = Metric("citationsAreReal")
    static let faithful = ScoreDimension(
        "faithful",
        description: "The answer states only what the journal excerpts in the reference say, with no invented people, events, or causes.",
        scale: .passFail(passDescription: "Only what the excerpts say", failDescription: "Adds something the excerpts don’t say")
    )

    /// The question is the prompt; `expected` carries the excerpts the answer must stay within.
    var dataset: ArrayLoader<ModelSample<String>> {
        let excerpts = LiveEvidenceFixtures.evidence.map { "\($0.id): \($0.snippet)" }.joined(separator: "\n")
        return ArrayLoader(samples: LiveEvidenceFixtures.questions.map { question in
            ModelSample(prompt: question, expected: excerpts)
        })
    }

    nonisolated(nonsending) func subject(from sample: ModelSample<String>) async throws -> ModelSubject<String> {
        let question = sample.promptDescription
        let fallback = DeterministicEvidenceAnswerBuilder.answer(question: question, evidence: LiveEvidenceFixtures.evidence, persona: livePersona)
        let answer = try await FoundationModelsEvidenceResponder().respond(
            question: question,
            evidence: LiveEvidenceFixtures.evidence,
            persona: livePersona,
            fallback: fallback
        ) ?? fallback
        let cited = Set(answer.observations.flatMap(\.evidenceIDs))
        // The value is the answer text plus its citations, so both evaluators see the same thing.
        let text = ([answer.summary] + answer.observations.map(\.text)).joined(separator: " ")
        return ModelSubject(value: text + "\ncited: " + cited.sorted().joined(separator: ","))
    }

    @EvaluatorsBuilder<ModelSample<String>, ModelSubject<String>>
    var evaluators: [any EvaluatorProtocol<ModelSample<String>, ModelSubject<String>>] {
        Evaluator<ModelSample<String>> { _, subject in
            let allowed = Set(LiveEvidenceFixtures.evidence.map(\.id))
            let citedLine = subject.value.components(separatedBy: "\ncited: ").last ?? ""
            let cited = citedLine.split(separator: ",").map(String.init)
            return cited.allSatisfy(allowed.contains)
                ? Self.citationsAreReal.passing()
                : Self.citationsAreReal.failing(rationale: "Cited \(cited.joined(separator: ", "))")
        }
        ModelJudgeEvaluator<ModelSample<String>>(judge: SystemLanguageModel.default, dimensions: [Self.faithful])
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: Self.citationsAreReal)
        aggregator.computeMean(of: Self.faithful.metric)
    }
}
#endif
