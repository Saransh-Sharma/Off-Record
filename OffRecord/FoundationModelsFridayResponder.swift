//
//  FoundationModelsFridayResponder.swift
//  OffRecord
//
//  Optional iOS 26 response layer for evidence-backed Friday answers.
//  Retrieval and citation validation stay deterministic.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
@Generable
struct GeneratedEvidenceObservation {
    let text: String
    let evidenceIDs: [String]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedEvidenceBackedFridayAnswer {
    let summary: String
    let observations: [GeneratedEvidenceObservation]
    let confidence: Double
    let followUpPrompt: String
    let limitations: String?
}

@available(iOS 26.0, *)
enum FoundationModelsFridayResponder {
    static func answer(
        question: String,
        evidence: [EvidenceReference],
        fallback: EvidenceBackedFridayAnswer
    ) async throws -> EvidenceBackedFridayAnswer? {
        let model = SystemLanguageModel.default
        guard model.availability == .available else { return nil }
        guard !evidence.isEmpty else { return nil }

        let evidenceIDs = Set(evidence.map(\.id))
        let evidenceBlock = evidence.enumerated().map { index, item in
            """
            Evidence \(index + 1)
            id: \(item.id)
            date: \(item.date.formatted(date: .abbreviated, time: .omitted))
            mood: \(item.mood ?? "unknown")
            snippet: \(item.snippet)
            """
        }
        .joined(separator: "\n\n")

        let session = LanguageModelSession(
            model: model,
            instructions: """
            You are Friday inside a private journal app. Answer only from the provided evidence.
            Every substantive observation must be supported by one or more evidenceIDs from the evidence list.
            If the evidence is weak, say so in limitations. Do not invent people, events, dates, moods, or causes.
            Keep the answer concise, warm, and specific.
            """
        )

        let response = try await session.respond(
            to: """
            User question:
            \(question)

            Retrieved journal evidence:
            \(evidenceBlock)

            Produce an evidence-backed answer. Use only evidenceIDs from the list.
            """,
            generating: GeneratedEvidenceBackedFridayAnswer.self,
            options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 420)
        )

        let generated = response.content
        let observations = generated.observations.compactMap { observation -> EvidenceObservation? in
            let citedIDs = observation.evidenceIDs.filter { evidenceIDs.contains($0) }
            guard !observation.text.isEmpty, !citedIDs.isEmpty else { return nil }
            return EvidenceObservation(text: observation.text, evidenceIDs: citedIDs)
        }
        let citedIDs = Set(observations.flatMap(\.evidenceIDs))
        guard !citedIDs.isEmpty else { return nil }

        let citedEvidence = evidence.filter { citedIDs.contains($0.id) }
        let confidence = min(max(generated.confidence, 0), fallback.confidence)

        return EvidenceBackedFridayAnswer(
            summary: generated.summary.isEmpty ? fallback.summary : generated.summary,
            observations: observations.isEmpty ? fallback.observations : observations,
            evidence: citedEvidence,
            confidence: confidence,
            followUpPrompt: generated.followUpPrompt.isEmpty ? fallback.followUpPrompt : generated.followUpPrompt,
            limitations: generated.limitations ?? fallback.limitations
        )
    }
}
#endif
