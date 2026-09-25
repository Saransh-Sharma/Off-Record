import Foundation
import Testing
@testable import AssistantCoreKit
import JournalFoundation
import SemanticMemoryKit

private let testPersona = AssistantPersona(
    id: "friday",
    name: "Friday",
    hostAppName: "OffRecord",
    evidenceSystemPromptTemplate: "You are {name} inside a private journal app. Answer only from the provided evidence.",
    copy: PersonaCopyCatalog(
        welcome: "I'm Friday. Tell me what you're carrying, or ask what I've noticed.",
        insufficientData: "I'm still learning your rhythm. Keep journaling and I'll get more useful.",
        noticedPrefix: "I'm noticing this from your entries so far: ",
        watchingSuffix: " I'll keep watching this with you.",
        exclusionRespected: "I don't have anything on that.",
        riskSafeSupport: "That sounds heavy. I'm here with you. It might also help to talk to someone you trust."
    )
)

private func evidence(_ snippet: String, score: Double = 0.03) -> EvidenceReference {
    EvidenceReference(
        id: UUID().uuidString,
        entryID: UUID(),
        date: Date(timeIntervalSince1970: 1_750_000_000),
        mood: "calm",
        snippet: snippet,
        chunkText: snippet,
        score: score,
        matchReason: .meaning
    )
}

struct DeterministicEvidenceAnswerBuilderTests {

    @Test func emptyEvidenceYieldsInsufficientDataCopy() {
        let answer = DeterministicEvidenceAnswerBuilder.answer(question: "q", evidence: [], persona: testPersona)
        #expect(answer.summary == testPersona.copy.insufficientData)
        #expect(answer.confidence == 0)
        #expect(answer.evidence.isEmpty)
    }

    @Test func evidenceProducesCitedObservations() {
        let refs = [evidence("walked by the lake"), evidence("stressful deadline day")]
        let answer = DeterministicEvidenceAnswerBuilder.answer(question: "how were my days", evidence: refs, persona: testPersona)
        #expect(answer.observations.count == 2)
        #expect(answer.observations.allSatisfy { !$0.evidenceIDs.isEmpty })
        #expect(answer.summary.hasPrefix(testPersona.copy.noticedPrefix))
        #expect(answer.confidence > 0)
        #expect(answer.limitations != nil) // fewer than 3 entries
    }

    @Test func confidenceGrowsWithEvidenceButCaps() {
        let few = DeterministicEvidenceAnswerBuilder.answer(question: "q", evidence: [evidence("a")], persona: testPersona)
        let many = DeterministicEvidenceAnswerBuilder.answer(
            question: "q",
            evidence: (0..<10).map { evidence("entry \($0)") },
            persona: testPersona
        )
        #expect(many.confidence > few.confidence)
        #expect(many.confidence <= 0.72)
        #expect(many.limitations == nil)
    }
}

struct EvidenceRespondingProtocolTests {

    struct StubResponder: EvidenceResponding {
        var result: EvidenceBackedAnswer?
        func respond(question: String, evidence: [EvidenceReference], persona: AssistantPersona, fallback: EvidenceBackedAnswer) async throws -> EvidenceBackedAnswer? {
            result
        }
    }

    @Test func stubReturnsInjectedAnswerOrNil() async throws {
        let fallback = DeterministicEvidenceAnswerBuilder.answer(question: "q", evidence: [evidence("x")], persona: testPersona)
        let improved = EvidenceBackedAnswer(
            summary: "Model summary",
            observations: fallback.observations,
            evidence: fallback.evidence,
            confidence: 0.5,
            followUpPrompt: nil,
            limitations: nil
        )
        let hit = try await StubResponder(result: improved).respond(question: "q", evidence: [], persona: testPersona, fallback: fallback)
        #expect(hit?.summary == "Model summary")
        let miss = try await StubResponder(result: nil).respond(question: "q", evidence: [], persona: testPersona, fallback: fallback)
        #expect(miss == nil)
    }
}

struct PersonaCopySafetyAuditTests {

    /// Both personas' user-facing copy must stay non-clinical.
    @Test func personaCopyContainsNoClinicalLanguage() {
        let evaCopy = PersonaCopyCatalog(
            welcome: "I'm Eva. Ask me about your days, or what I've noticed.",
            insufficientData: "I don't have enough journal context yet. Keep capturing and I'll get more useful.",
            noticedPrefix: "From your journal, ",
            watchingSuffix: " I'll keep an eye on this with you.",
            exclusionRespected: "I don't have anything on that.",
            riskSafeSupport: "That sounds heavy. I'm here with you. It might also help to talk to someone you trust."
        )
        for copy in [testPersona.copy, evaCopy] {
            let strings = [copy.welcome, copy.insufficientData, copy.noticedPrefix, copy.watchingSuffix, copy.exclusionRespected, copy.riskSafeSupport]
            for text in strings {
                #expect(SensitiveDomainPolicy.clinicalTermViolations(in: text).isEmpty, "clinical term in: \(text)")
            }
        }
    }

    @Test func evidencePromptResolvesPersona() {
        #expect(testPersona.evidenceSystemPrompt == "You are Friday inside a private journal app. Answer only from the provided evidence.")
    }

    @Test func supportOnlyModeForHighRisk() {
        #expect(SensitiveDomainPolicy.standard.responseMode(for: .highRiskExcluded) == .supportOnly)
    }
}
