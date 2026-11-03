import Foundation
import Testing
@testable import JournalFoundation

struct JournalAIExclusionTests {

    @Test func includedPermitsEverything() {
        let exclusion = JournalAIExclusion.included
        #expect(exclusion.permitsSemanticIndexing)
        #expect(exclusion.permitsAssistantEvidence)
        #expect(exclusion.permitsReflection)
        #expect(exclusion.permitsReflectionQuotes)
    }

    @Test func excludedFromAIStillCountsInReflectionWithoutQuotes() {
        let exclusion = JournalAIExclusion.excludedFromAI
        #expect(!exclusion.permitsSemanticIndexing)
        #expect(!exclusion.permitsAssistantEvidence)
        #expect(exclusion.permitsReflection)
        #expect(!exclusion.permitsReflectionQuotes)
    }

    @Test func fullyExcludedIsInvisibleEverywhere() {
        let exclusion = JournalAIExclusion.excludedFromAIAndReflection
        #expect(!exclusion.permitsSemanticIndexing)
        #expect(!exclusion.permitsAssistantEvidence)
        #expect(!exclusion.permitsReflection)
        #expect(!exclusion.permitsReflectionQuotes)
    }

    @Test func codableRoundTripPreservesEveryCase() throws {
        for exclusion in JournalAIExclusion.allCases {
            let data = try JSONEncoder().encode(exclusion)
            let decoded = try JSONDecoder().decode(JournalAIExclusion.self, from: data)
            #expect(decoded == exclusion)
        }
    }
}

struct JournalSnapshotTests {

    private func makeSnapshot(blocks: [JournalBlockSnapshot]) -> JournalSnapshot {
        JournalSnapshot(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            blocks: blocks
        )
    }

    @Test func plainTextJoinsTextBlocksInSortOrder() {
        let now = Date()
        let snapshot = makeSnapshot(blocks: [
            JournalBlockSnapshot(id: UUID(), kind: .text, text: "second", sortOrder: 1, createdAt: now),
            JournalBlockSnapshot(id: UUID(), kind: .voiceTranscript, text: "first", sortOrder: 0, createdAt: now),
            JournalBlockSnapshot(id: UUID(), kind: .photo, attachmentID: UUID(), sortOrder: 2, createdAt: now),
        ])
        #expect(snapshot.plainText == "first\nsecond")
        #expect(snapshot.wordCount == 2)
    }

    @Test func defaultExclusionIsIncluded() {
        let snapshot = makeSnapshot(blocks: [])
        #expect(snapshot.aiExclusion == .included)
    }

    @Test func codableRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var snapshot = makeSnapshot(blocks: [
            JournalBlockSnapshot(id: UUID(), kind: .mood, moodToken: "calm", createdAt: now)
        ])
        snapshot.aiExclusion = .excludedFromAI
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(JournalSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }
}

struct JournalAttachmentTests {
    @Test func lifecycleMakesRecoveryAndRetentionExplicit() {
        #expect(JournalAttachmentAvailability.pending.canRetryRecovery)
        #expect(JournalAttachmentAvailability.unavailable.canRetryRecovery)
        #expect(!JournalAttachmentAvailability.permanentlyMissing.canRetryRecovery)
        #expect(!JournalAttachmentAvailability.deleted.shouldRetainMetadata)
        #expect(JournalAttachmentAvailability.permanentlyMissing.shouldRetainMetadata)
    }

    @Test func metadataRoundTripsWithoutAHostPersistenceType() throws {
        let snapshot = JournalAttachmentSnapshot(
            id: UUID(),
            entryID: UUID(),
            kind: .audio,
            availability: .locallyAvailable,
            fileName: "voice.m4a",
            mimeType: "audio/mp4",
            byteCount: 512,
            checksum: "abc",
            sourceCaptureID: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            duration: 12.5
        )
        let decoded = try JSONDecoder().decode(
            JournalAttachmentSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        #expect(decoded == snapshot)
    }
}

struct AssistantPersonaTests {

    private let persona = AssistantPersona(
        id: "friday",
        name: "Friday",
        hostAppName: "OffRecord",
        evidenceSystemPromptTemplate: "You are {name} inside a private journal app called {app}. Answer only from the provided evidence.",
        copy: PersonaCopyCatalog(
            welcome: "I'm Friday. Tell me what you're carrying, or ask what I've noticed.",
            insufficientData: "I'm still learning your rhythm. Keep journaling and I'll get more useful.",
            noticedPrefix: "I'm noticing this from your entries so far: ",
            watchingSuffix: " I'll keep watching this with you.",
            exclusionRespected: "I don't have anything on that.",
            riskSafeSupport: "That sounds heavy. I'm here with you, and it might help to talk to someone you trust."
        )
    )

    @Test func evidenceSystemPromptResolvesPlaceholders() {
        let prompt = persona.evidenceSystemPrompt
        #expect(prompt.contains("You are Friday"))
        #expect(prompt.contains("OffRecord"))
        #expect(!prompt.contains("{name}"))
        #expect(!prompt.contains("{app}"))
    }

    @Test func noticedAndWatchingComposeCopy() {
        #expect(persona.noticed("mornings are hard") == "I'm noticing this from your entries so far: mornings are hard")
        #expect(persona.watching("Sleep keeps coming up.") == "Sleep keeps coming up. I'll keep watching this with you.")
    }
}

struct SensitiveDomainPolicyTests {

    @Test func standardPolicyLadder() {
        let policy = SensitiveDomainPolicy.standard
        #expect(policy.responseMode(for: .none) == .normal)
        #expect(policy.responseMode(for: .mildDistress) == .gentle)
        #expect(policy.responseMode(for: .moderateConcern) == .gentle)
        #expect(policy.responseMode(for: .highRiskExcluded) == .supportOnly)
    }

    @Test func safetyLevelsAreOrdered() {
        #expect(JournalSafetyLevel.none < .mildDistress)
        #expect(JournalSafetyLevel.mildDistress < .moderateConcern)
        #expect(JournalSafetyLevel.moderateConcern < .highRiskExcluded)
    }

    @Test func clinicalTermAuditFindsViolations() {
        let violations = SensitiveDomainPolicy.clinicalTermViolations(
            in: "We can't diagnose you, but this looks like a disorder."
        )
        #expect(violations.contains("diagnose"))
        #expect(violations.contains("disorder"))
        #expect(SensitiveDomainPolicy.clinicalTermViolations(in: "You had calmer evenings this week.").isEmpty)
    }
}

struct JournalRiskClassifierTests {

    @Test func directSelfHarmLanguageIsHighRisk() {
        for text in [
            "I thought about suicide last night.",
            "Some days I want to kill myself.",
            "I started cutting myself again",
            "I don’t want to be alive anymore",
            "I just want to end it all",
        ] {
            #expect(JournalRiskClassifier.level(for: text) == .highRiskExcluded, "\(text)")
        }
    }

    @Test func indirectWordingIsHighRisk() {
        for text in [
            "Everyone would be better off without me.",
            "Sometimes I think it would be easier if I wasn't here",
            "I keep wishing I could disappear forever",
            "There's no reason to live like this",
        ] {
            #expect(JournalRiskClassifier.level(for: text) == .highRiskExcluded, "\(text)")
        }
    }

    @Test func figuresOfSpeechAreNotFlagged() {
        for text in [
            "This commute is killing me",
            "I'm dying to see the new movie",
            "I laughed so hard I almost died",
            "My phone battery died again",
            "I can't wait for this project to be over",
            "I want to disappear into a good book this weekend",
            "Self-care Sunday: a long walk and tea",
        ] {
            #expect(JournalRiskClassifier.level(for: text) == .none, "\(text)")
        }
    }

    @Test func hopelessnessIsModerateAndStressIsMild() {
        #expect(JournalRiskClassifier.level(for: "Everything feels hopeless lately") == .moderateConcern)
        #expect(JournalRiskClassifier.level(for: "I can’t cope with this week") == .moderateConcern)
        #expect(JournalRiskClassifier.level(for: "Work left me overwhelmed") == .mildDistress)
        #expect(JournalRiskClassifier.level(for: "I panicked before the call") == .mildDistress)
    }

    @Test func phrasesMatchWholeWordsOnly() {
        #expect(JournalRiskClassifier.level(for: "The number of tasks was fine") == .none)
        #expect(JournalRiskClassifier.level(for: "suicidesquad rewatch") == .none)
    }

    @Test func highestLevelWinsAcrossTexts() {
        let level = JournalRiskClassifier.level(forAll: ["A calm day", "Felt overwhelmed", "I want to die"])
        #expect(level == .highRiskExcluded)
        #expect(JournalRiskClassifier.level(forAll: [String]()) == .none)
    }

    @Test func standardPolicyMapsHighRiskToSupportOnly() {
        #expect(JournalRiskClassifier.responseMode(for: "I want to hurt myself") == .supportOnly)
        #expect(JournalRiskClassifier.responseMode(for: "I feel hopeless") == .gentle)
        #expect(JournalRiskClassifier.responseMode(for: "Lunch with Maya") == .normal)
    }
}
