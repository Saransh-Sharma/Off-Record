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
        try await FoundationModelsEvidenceResponder().respond(
            question: question,
            evidence: evidence,
            persona: .friday,
            fallback: fallback
        )
    }
}
#endif
