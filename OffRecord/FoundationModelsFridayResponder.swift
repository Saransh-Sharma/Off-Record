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

extension AssistantPersona {
    /// Friday, OffRecord's journal companion.
    static let friday = AssistantPersona(
        id: "friday",
        name: "Friday",
        hostAppName: "OffRecord",
        evidenceSystemPromptTemplate: "You are {name} inside a private journal app. Answer only from the provided evidence.",
        copy: PersonaCopyCatalog(
            welcome: "I'm Friday. Tell me what you're carrying, or ask what I've noticed.",
            insufficientData: FridayPersonality.insufficientData,
            noticedPrefix: "I'm noticing this from your entries so far: ",
            watchingSuffix: " I'll keep watching this with you.",
            exclusionRespected: "I don't have anything on that.",
            riskSafeSupport: "That sounds heavy. I'm here with you. It might also help to talk to someone you trust."
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
        try await FoundationModelsEvidenceResponder().respond(
            question: question,
            evidence: evidence,
            persona: .friday,
            fallback: fallback
        )
    }
}
#endif
