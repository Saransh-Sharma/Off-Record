#if canImport(Evaluations)
import Foundation
import FoundationModels
import Testing
@_weakLinked import Evaluations
@testable import OffRecord

/// The Friday grounding suite on Apple's Evaluations framework (iOS 27).
///
/// - `FridayGoldenGroundingEvaluation` runs the same golden cases as
///   `FridayGroundingTests` through the validators. No model; it runs anywhere
///   iOS 27 does.
/// - `FridayLiveGoDeeperEvaluation` asks the real on-device model for Go Deeper
///   questions and scores them with the validator and an on-device judge. It
///   is opt-in (`TEST_RUNNER_OFFRECORD_LIVE_MODEL=1`) and skips cleanly
///   without Apple Intelligence.
///
/// The iOS 26 mock-based suites stay as they are; this adds a second view.
@MainActor
@Suite(.serialized)
struct FridayGroundingEvaluationTests {
    @Test func goldenGroundingEvaluationMatchesEveryCase() async throws {
        guard #available(iOS 27.0, *) else { return }
        let result = try await FridayGoldenGroundingEvaluation().run()
        #expect(!result.errors.hasFailures)
        #expect(result.aggregateValue(.mean(of: FridayGoldenGroundingEvaluation.matchesGolden)) == 1)
    }

    @Test(.enabled(if: FridayLiveModel.isEnabled, "Needs OFFRECORD_LIVE_MODEL=1 and the on-device model"))
    func liveGoDeeperQuestionsAreGroundedOrRejected() async throws {
        guard #available(iOS 27.0, *) else { return }
        let result = try await FridayLiveGoDeeperEvaluation().run()
        print(result.groupedSummary)
        #expect(result.errors.anyInferenceProduced)
        // The contract, not the model's skill: whatever passes validation is
        // what Friday shows; the rest falls back to templates. Record the rate.
        let passRate = result.aggregateValue(.mean(of: FridayLiveGoDeeperEvaluation.passesValidation))
        #expect((0...1).contains(passRate))
    }
}

/// The verdict for one golden case: what Friday shows, or nil for rejected.
struct GroundingVerdict: Codable, Equatable, Sendable {
    let shown: String?
}

@available(iOS 27.0, *)
struct GoldenGroundingSample: SampleProtocol {
    let golden: GroundingGolden

    var input: String { "\(golden.kind.rawValue): \(golden.raw)" }
    var expected: GroundingVerdict? { GroundingVerdict(shown: golden.shown) }
}

@available(iOS 27.0, *)
struct FridayGoldenGroundingEvaluation: Evaluation {
    static let matchesGolden = Metric("matchesGolden")

    var dataset: ArrayLoader<GoldenGroundingSample> {
        ArrayLoader(samples: FridayGroundingGoldens.runnable.map(GoldenGroundingSample.init))
    }

    nonisolated(nonsending) func subject(from sample: GoldenGroundingSample) async throws -> ModelSubject<GroundingVerdict> {
        ModelSubject(value: GroundingVerdict(shown: sample.golden.validate()))
    }

    @EvaluatorsBuilder<GoldenGroundingSample, ModelSubject<GroundingVerdict>>
    var evaluators: [any EvaluatorProtocol<GoldenGroundingSample, ModelSubject<GroundingVerdict>>] {
        Evaluator<GoldenGroundingSample> { sample, subject in
            subject.value == sample.expected
                ? Self.matchesGolden.passing()
                : Self.matchesGolden.failing(rationale: "\(sample.golden.note): got \(subject.value.shown ?? "rejected")")
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: Self.matchesGolden)
    }
}

/// Real Go Deeper questions from the on-device model. Each sample's prompt is
/// what the app sends; `expected` carries the entry the question must stay within.
@available(iOS 27.0, *)
struct FridayLiveGoDeeperEvaluation: Evaluation {
    static let passesValidation = Metric("passesValidation")
    static let grounded = ScoreDimension(
        "grounded",
        description: "The question mentions only people, places, and topics that appear in the reference entry.",
        scale: .passFail(passDescription: "Only things from the entry", failDescription: "Mentions something the entry doesn’t")
    )

    static let entries = [
        FridayGroundingGoldens.lunch,
        FridayGroundingGoldens.deadline,
        "Cooked dinner with Arjun and planted tomatoes in the garden before the rain came in.",
        "Finished the first draft of the grant application and sent it to Priya for comments.",
    ]

    var dataset: ArrayLoader<ModelSample<String>> {
        ArrayLoader(samples: Self.entries.map { entry in
            ModelSample(
                prompt: EntryGenerationContext(text: entry, mood: .none).promptBlock + "\n\nWrite the question.",
                expected: entry,
                instructions: FoundationModelsEntryQuestionGenerator.instructions
            )
        })
    }

    nonisolated(nonsending) func subject(from sample: ModelSample<String>) async throws -> ModelSubject<String> {
        let context = EntryGenerationContext(text: sample.expected ?? "", mood: .none)
        let raw = try await FoundationModelsEntryQuestionGenerator().question(for: context)
        return ModelSubject(value: raw ?? "")
    }

    @EvaluatorsBuilder<ModelSample<String>, ModelSubject<String>>
    var evaluators: [any EvaluatorProtocol<ModelSample<String>, ModelSubject<String>>] {
        Evaluator<ModelSample<String>> { sample, subject in
            let context = EntryGenerationContext(text: sample.expected ?? "", mood: .none)
            return GoDeeperQuestionValidator.validated(subject.value, context: context) != nil
                ? Self.passesValidation.passing()
                : Self.passesValidation.failing(rationale: subject.value)
        }
        // The judge is the same on-device model; nothing leaves the device.
        ModelJudgeEvaluator<ModelSample<String>>(judge: SystemLanguageModel.default, dimensions: [Self.grounded])
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: Self.passesValidation)
        aggregator.computeMean(of: Self.grounded.metric)
    }
}
#endif
