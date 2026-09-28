//
//  FoundationModelsEvidenceResponder.swift
//  AssistantCoreKit
//
//  Optional iOS 26 response layer for evidence-backed answers. Retrieval and
//  citation validation stay deterministic; the persona only shapes the voice.
//

import Foundation
import JournalFoundation
import SemanticMemoryKit

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedEvidenceObservation {
    @Guide(description: "One short sentence about what the cited entries show.")
    let text: String
    let evidenceIDs: [String]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedEvidenceBackedAnswer {
    @Guide(description: "The answer in at most 2 short sentences.")
    let summary: String
    @Guide(description: "Specific findings from the evidence, each one sentence.")
    let observations: [GeneratedEvidenceObservation]
    let confidence: Double
    let followUpPrompt: String
    @Guide(description: "At most 1 sentence about what the evidence can’t show. Omit when there is nothing to add.")
    let limitations: String?
}

@available(iOS 26.0, macOS 26.0, *)
public struct FoundationModelsEvidenceResponder: EvidenceResponding {

    public init() {}

    public static var isModelAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    public func respond(
        question: String,
        evidence: [EvidenceReference],
        persona: AssistantPersona,
        fallback: EvidenceBackedAnswer
    ) async throws -> EvidenceBackedAnswer? {
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
            \(persona.evidenceSystemPrompt)
            Every substantive observation must be supported by one or more evidenceIDs from the evidence list.
            Do not invent people, events, dates, moods, or causes.
            Speak to the user as "you" and about yourself as "I". Use 1–3 short sentences in plain words.
            Lead with what the entries show and include dates or counts. No exclamation marks, emoji, or em dashes.
            Never use therapy phrases (valid, safe space, journey, gentle, self-care) or clinical or diagnostic language.
            If evidence is thin, say "I’m not sure" once in limitations.
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
            generating: GeneratedEvidenceBackedAnswer.self,
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

        return EvidenceBackedAnswer(
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
