//
//  FoundationModelsFridayResponder.swift
//  OffRecord
//
//  Friday-facing wrapper over the shared AssistantCoreKit responder.
//  Retrieval and citation validation stay deterministic; the shared layer
//  only phrases the evidence in Friday's voice.
//

import Foundation
import JournalFoundation
import SemanticMemoryKit

extension AssistantPersona {
    /// Friday, OffRecord's journal companion.
    static let friday = AssistantPersona(
        id: "friday",
        name: "Friday",
        hostAppName: "OffRecord",
        evidenceSystemPromptTemplate: "You are {name} inside a private journal app. Answer only from the provided evidence.",
        copy: PersonaCopyCatalog(
            welcome: FridayPersonality.welcome,
            insufficientData: FridayPersonality.insufficientData,
            // Friday speaks plainly: no lead-in before what she sees, no sign-off after.
            noticedPrefix: "",
            watchingSuffix: "",
            exclusionRespected: FridayPersonality.exclusionRespected,
            riskSafeSupport: FridayPersonality.riskSafeSupport
        )
    )
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
enum FoundationModelsFridayResponder {
    static func answer(
        question: String,
        evidence: [EvidenceReference],
        fallback: EvidenceBackedFridayAnswer
    ) async throws -> EvidenceBackedFridayAnswer? {
        let generated = try await FoundationModelsEvidenceResponder().respond(
            question: question,
            evidence: evidence,
            persona: .friday,
            fallback: fallback
        )
        return generated.flatMap { FridayAnswerValidator.validated($0, question: question, evidence: evidence) }
    }
}
#endif

/// Checks a model-phrased chat answer before it replaces the deterministic one.
enum FridayAnswerValidator {
    /// The answer with its wording normalized, or nil when any part breaks the
    /// Voice or safety rules, names someone the evidence doesn't, or cites
    /// nothing it was given.
    static func validated(
        _ answer: EvidenceBackedFridayAnswer,
        question: String,
        evidence: [EvidenceReference]
    ) -> EvidenceBackedFridayAnswer? {
        let allowedIDs = Set(evidence.map(\.id))
        let cited = answer.observations.flatMap(\.evidenceIDs)
        guard !cited.isEmpty, cited.allSatisfy(allowedIDs.contains) else { return nil }

        // A heavy question may be echoed back; nothing may read as high-risk.
        let allowedRisk = max(JournalSafetyLevel.mildDistress, min(JournalRiskClassifier.level(for: question), JournalSafetyLevel.moderateConcern))
        let source = ([question] + evidence.map(\.chunkText)).joined(separator: "\n")
        func clean(_ text: String) -> String? {
            let value = FridayOutputValidator.normalized(text)
            guard FridayOutputValidator.isAcceptable(value, allowedRisk: allowedRisk),
                  FridayOutputValidator.inventedNames(in: value, source: source).isEmpty else { return nil }
            return value
        }

        guard let summary = clean(answer.summary) else { return nil }
        var observations: [EvidenceObservation] = []
        for observation in answer.observations {
            guard let text = clean(observation.text) else { return nil }
            observations.append(EvidenceObservation(text: text, evidenceIDs: observation.evidenceIDs))
        }
        var limitations: String?
        if let raw = answer.limitations, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let value = clean(raw) else { return nil }
            limitations = value
        }
        return EvidenceBackedFridayAnswer(
            summary: summary,
            observations: observations,
            evidence: answer.evidence.filter { allowedIDs.contains($0.id) },
            confidence: answer.confidence,
            // Follow-ups come from FridayFollowUpBuilder, never the model.
            followUpPrompt: nil,
            limitations: limitations,
            responseMode: answer.responseMode
        )
    }
}
