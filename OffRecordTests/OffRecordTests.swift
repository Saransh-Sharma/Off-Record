//
//  OffRecordTests.swift
//  OffRecordTests
//
//  Created by Karthikeyan NG on 01/12/25.
//

import Testing
import Foundation
import SwiftUI
import CryptoKit
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif
@testable import OffRecord

// MARK: - Semantic Memory Tests

struct SemanticMemoryTests {

    @Test func shortEntryStaysSingleChunk() {
        let chunks = MemoryChunker.chunks(for: "I felt calm after walking home from work.")

        #expect(chunks.count == 1)
        #expect(chunks[0].text == "I felt calm after walking home from work.")
        #expect(chunks[0].characterStart == 0)
    }

    @Test func longEntryChunksOnSentenceBoundaries() {
        let sentence = "Work felt tense, but the evening walk helped me settle."
        let text = Array(repeating: sentence, count: 30).joined(separator: " ")
        let chunks = MemoryChunker.chunks(for: text, targetWords: 40, overlapWords: 8)

        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { !$0.text.isEmpty })
        #expect(chunks.allSatisfy { $0.characterEnd > $0.characterStart })
    }

    @Test func textHashIsStable() {
        let first = TextSignals.hash("same journal text")
        let second = TextSignals.hash("same journal text")
        let third = TextSignals.hash("different journal text")

        #expect(first == second)
        #expect(first != third)
    }

    @Test func vectorNormalizationProducesUnitMagnitude() {
        let vector = VectorMath.normalized([3, 4])
        let magnitude = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })

        #expect(abs(magnitude - 1) < 0.0001)
    }

    @Test func cosineSimilarityUsesDotProductForNormalizedVectors() {
        let lhs = VectorMath.normalized([1, 0, 0])
        let rhs = VectorMath.normalized([1, 0, 0])
        let unrelated = VectorMath.normalized([0, 1, 0])

        #expect(VectorMath.cosine(lhs, rhs) > 0.99)
        #expect(VectorMath.cosine(lhs, unrelated) < 0.01)
    }

    @Test func hybridSearchPreservesExactNameRanking() {
        let entryID = UUID()
        let exact = makeChunk(
            id: "exact",
            entryID: entryID,
            text: "Dinner with Maya helped me feel less alone.",
            vector: VectorMath.normalized([0.1, 0.1, 0.8]),
            entities: ["Maya"],
            topics: ["dinner", "maya"]
        )
        let semanticOnly = makeChunk(
            id: "semantic",
            entryID: UUID(),
            text: "A quiet walk made the day feel lighter.",
            vector: VectorMath.normalized([0.1, 0.1, 0.8]),
            entities: [],
            topics: ["walk"]
        )

        let results = HybridMemorySearchService.search(
            query: "Maya",
            chunks: [semanticOnly, exact],
            queryVector: VectorMath.normalized([0.1, 0.1, 0.8]),
            lexicalHits: [
                LexicalHit(chunkID: "exact", reason: .exact)
            ],
            limit: 2
        )

        #expect(results.first?.chunk.id == "exact")
        #expect(results.first?.reason == .exact || results.first?.reason == .entity)
    }

    private func makeChunk(
        id: String,
        entryID: UUID,
        text: String,
        vector: [Float],
        entities: [String],
        topics: [String]
    ) -> MemoryChunk {
        MemoryChunk(
            id: id,
            entryID: entryID,
            chunkIndex: 0,
            date: Date(),
            mood: nil,
            textHash: TextSignals.hash(text),
            entryTextHash: TextSignals.hash(text),
            characterStart: 0,
            characterEnd: text.count,
            entities: entities,
            topics: topics,
            embeddingModelID: "test",
            embeddingRevision: 1,
            embeddingDimension: vector.count,
            language: "en",
            vector: vector,
            isStarred: false
        )
    }

    @Test func typedSearchResultRepresentsBuildingState() {
        let result = SemanticMemorySearchResult.building(progress: 0.42, message: "Indexing")

        if case .building(let progress, let message) = result {
            #expect(progress == 0.42)
            #expect(message == "Indexing")
        } else {
            Issue.record("Expected building state")
        }
    }

    @Test func fridayRefusesWithoutEvidence() async {
        let answer = await EvidenceFridayEngine.answer(question: "What stresses me out?", evidence: [])

        #expect(answer.evidence.isEmpty)
        #expect(answer.confidence == 0)
        #expect(answer.summary.contains("not have enough journal evidence"))
    }

    @Test func fridayRefusesWeakMeaningOnlyEvidence() async {
        let evidence = EvidenceReference(
            id: "weak",
            entryID: UUID(),
            date: Date(),
            mood: nil,
            snippet: "A loosely related memory.",
            chunkText: "A loosely related memory.",
            score: 0.004,
            matchReason: .meaning
        )

        let answer = await EvidenceFridayEngine.answer(question: "What stresses me out?", evidence: [evidence])

        #expect(answer.evidence.isEmpty)
        #expect(answer.confidence == 0)
        #expect(answer.limitations?.localizedCaseInsensitiveContains("retrieved journal evidence") == true)
    }

    @Test func fridayObservationsCarryEvidenceIDs() async {
        let evidence = EvidenceReference(
            id: "e1",
            entryID: UUID(),
            date: Date(),
            mood: "reflective",
            snippet: "Work pressure was heavy after the meeting.",
            chunkText: "Work pressure was heavy after the meeting.",
            score: 0.03,
            matchReason: .exact
        )

        let answer = await EvidenceFridayEngine.answer(question: "work pressure", evidence: [evidence])

        #expect(!answer.evidence.isEmpty)
        #expect(answer.observations.allSatisfy { !$0.evidenceIDs.isEmpty })
    }

    @Test func semanticStoreInvalidatesSchemaMismatch() throws {
        let text = "Dinner with Maya in Bangalore helped me feel grounded."
        let chunk = makeChunk(
            id: "schema",
            entryID: UUID(),
            text: text,
            vector: VectorMath.normalized([1, 0, 0]),
            entities: ["Maya", "Bangalore"],
            topics: ["dinner", "bangalore"]
        )

        let snapshot = try SemanticMemoryTestSupport.loadSnapshotAfterSchemaMismatch(
            url: temporaryIndexURL(),
            chunk: chunk,
            text: text
        )

        #expect(snapshot == nil)
    }

    @Test func semanticStoreInvalidatesProviderMetadataMismatch() throws {
        let text = "Work pressure eased after the planning conversation."
        let chunk = makeChunk(
            id: "provider",
            entryID: UUID(),
            text: text,
            vector: VectorMath.normalized([0, 1, 0]),
            entities: [],
            topics: ["work", "pressure"]
        )

        let snapshot = try SemanticMemoryTestSupport.loadSnapshotAfterProviderMetadataMismatch(
            url: temporaryIndexURL(),
            chunk: chunk,
            text: text
        )

        #expect(snapshot == nil)
    }

    @Test func semanticIndexLifecycleUpsertsDeletesAndRemovesOrphans() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let workID = UUID()
        let cafeID = UUID()
        let initialRecords = [
            IndexableEntry(
                id: workID,
                date: now,
                mood: "tense",
                text: "The quarterly review brought work stress and pressure.",
                isStarred: false
            ),
            IndexableEntry(
                id: cafeID,
                date: now.addingTimeInterval(-86_400),
                mood: "calm",
                text: "The Bangalore cafe made the afternoon feel lighter.",
                isStarred: false
            )
        ]
        let updatedRecord = IndexableEntry(
            id: workID,
            date: now,
            mood: "reflective",
            text: "Maya helped me reframe the work pressure after the sprint review.",
            isStarred: true
        )

        let result = try await SemanticMemoryTestSupport.exerciseLifecycle(
            url: temporaryIndexURL(),
            initialRecords: initialRecords,
            updatedRecord: updatedRecord,
            deletedEntryID: cafeID
        )

        #expect(result.initialChunkCount == 2)
        #expect(result.updatedChunkCount == 2)
        #expect(result.deletedChunkCount == 1)
        #expect(result.updatedSearchMatchedNewText)
        #expect(!result.deletedSearchHasRemovedEntry)
    }

    private func temporaryIndexURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OffRecordSemanticMemoryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return directory.appendingPathComponent("semantic-memory.sqlite")
    }
}

// MARK: - Mood Dial Performance Tests

struct MoodDialPerformanceTests {
    @Test func moodDialPersistenceOnlySavesChanges() {
        #expect(MoodDialPersistence.openingMood(for: .happy) == .happy)
        #expect(MoodDialPersistence.openingMood(for: .none) == .none)
        #expect(MoodDialPersistence.shouldSave(originalMood: .none, draftMood: .happy))
        #expect(!MoodDialPersistence.shouldSave(originalMood: .calm, draftMood: .calm))
    }

    @Test func wheelGeometryCacheBuildsOneSegmentPerDialMood() {
        MoodDialWheelGeometryCache.resetForTesting()
        let metrics = MoodDialWheelMetrics(size: CGSize(width: 402, height: 874))
        let geometry = MoodDialWheelGeometryCache.geometry(for: metrics)

        #expect(geometry.segments.count == Mood.dialMoods.count)
        #expect(geometry.segments.map(\.mood) == Mood.dialMoods)
        #expect(geometry.segment(for: Mood.none)?.mood == Mood.none)
    }

    @Test func recordingStateHasResponsiveStartingState() {
        var state = RecordingState.idle
        #expect(state == .idle)

        state = .starting
        #expect(state == .starting)

        state = .recording
        #expect(state == .recording)
    }
}

// MARK: - Proactive Reflection Tests

struct ProactiveReflectionTests {

    @Test func anomalyDetectionWaitsForEnoughHistory() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = (0..<5).map {
            makeReflectionEntry(daysAgo: $0, sentiment: -0.7, text: "A heavy day at work.", now: now)
        }

        let insights = ProactiveReflectionAnalyzer.detectAnomalies(in: entries, now: now)

        #expect(insights.isEmpty)
    }

    @Test func anomalyDetectionFlagsClearOutlier() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var entries = (1...11).map { day in
            makeReflectionEntry(
                daysAgo: day,
                sentiment: day.isMultiple(of: 2) ? 0.10 : 0.18,
                text: "A steady ordinary day with a walk.",
                now: now
            )
        }
        entries.append(makeReflectionEntry(daysAgo: 0, sentiment: -0.75, text: "I felt crushed and tense today.", now: now))

        let insights = ProactiveReflectionAnalyzer.detectAnomalies(in: entries, now: now)

        #expect(!insights.isEmpty)
        #expect(insights.allSatisfy { !$0.evidence.isEmpty })
    }

    @Test func comparativeSentimentAnomalyIncludesSourceAndBaselineEvidence() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var entries = (1...12).map { day in
            makeReflectionEntry(
                daysAgo: day,
                sentiment: 0.18,
                text: "A steady ordinary day with enough room to breathe.",
                now: now
            )
        }
        entries.append(makeReflectionEntry(daysAgo: 0, sentiment: -0.75, text: "I felt crushed and tense today.", now: now))

        let insight = ProactiveReflectionAnalyzer.detectAnomalies(in: entries, now: now).first { $0.title.contains("heavier") }

        #expect(insight?.evidence.contains { $0.role == .source } == true)
        #expect((insight?.evidence.filter { $0.role == .baseline }.count ?? 0) >= 2)
    }

    @Test func comparativeWordCountAnomalyIncludesBaselineEvidence() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var entries = (1...12).map { day in
            makeReflectionEntry(
                daysAgo: day,
                sentiment: 0.1,
                text: "Short steady note.",
                now: now
            )
        }
        let longText = Array(repeating: "I needed more space to name the day clearly.", count: 30).joined(separator: " ")
        entries.append(makeReflectionEntry(daysAgo: 0, sentiment: 0.1, text: longText, now: now))

        let insight = ProactiveReflectionAnalyzer.detectAnomalies(in: entries, now: now).first { $0.title.contains("more to say") }

        #expect(insight?.evidence.contains { $0.role == .source } == true)
        #expect((insight?.evidence.filter { $0.role == .baseline }.count ?? 0) >= 2)
    }

    @Test func decisionExtractionCapturesDecisionsAndRegretsOnly() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = makeReflectionEntry(
            daysAgo: 0,
            sentiment: -0.2,
            text: "I decided to decline the rushed timeline. I regret saying yes last month. I should go to sleep earlier.",
            now: now
        )

        let decisions = ProactiveReflectionAnalyzer.extractDecisionMoments(from: [entry], now: now)

        #expect(decisions.count == 2)
        #expect(decisions.contains { $0.kind == .decision && $0.phrase.localizedCaseInsensitiveContains("decided") })
        #expect(decisions.contains { $0.kind == .regret && $0.phrase.localizedCaseInsensitiveContains("regret") })
        #expect(!decisions.contains { $0.phrase.localizedCaseInsensitiveContains("sleep earlier") })
    }

    @Test func extractedDecisionsPreserveFollowUpStateAcrossRefresh() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entryID = UUID()
        let entry = makeReflectionEntry(
            id: entryID,
            daysAgo: 3,
            sentiment: -0.2,
            text: "I regret accepting the rushed project timeline.",
            now: now
        )
        let first = ProactiveReflectionAnalyzer.extractDecisionMoments(from: [entry], now: now)
        let existing = DecisionFollowUpState(
            id: first[0].followUp.id,
            decisionID: first[0].id,
            sourceEntryID: entryID,
            phraseHash: first[0].phraseHash,
            state: .reflected,
            firstSeenAt: now.addingTimeInterval(-100),
            lastPromptedAt: now.addingTimeInterval(-50),
            resolvedAt: now
        )

        let second = ProactiveReflectionAnalyzer.extractDecisionMoments(from: [entry], existingFollowUps: [existing], now: now)

        #expect(second.first?.followUp.state == .reflected)
        #expect(second.first?.followUp.resolvedAt == now)
    }

    @Test func weeklyRecapComparesCorrectWindows() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [
            makeReflectionEntry(daysAgo: 1, sentiment: 0.2, text: "I chose a calmer work rhythm.", now: now),
            makeReflectionEntry(daysAgo: 3, sentiment: 0.1, text: "Dinner helped me reset after deadlines.", now: now),
            makeReflectionEntry(daysAgo: 8, sentiment: -0.2, text: "Last week work felt tense.", now: now),
            makeReflectionEntry(daysAgo: 10, sentiment: -0.3, text: "Last week I was worried about deadlines.", now: now)
        ]
        let decisions = ProactiveReflectionAnalyzer.extractDecisionMoments(from: entries, now: now)

        let recap = ProactiveReflectionAnalyzer.makeWeeklyRecap(from: entries, decisions: decisions, now: now)

        #expect(recap?.currentWeekEntryCount == 2)
        #expect(recap?.previousWeekEntryCount == 2)
        #expect(recap?.decisionCount == 1)
    }

    @Test func contextPromptPrefersDueDecisionOverWeeklyPrompt() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [
            makeReflectionEntry(daysAgo: 3, sentiment: -0.2, text: "I regret accepting the rushed project timeline.", now: now),
            makeReflectionEntry(daysAgo: 1, sentiment: 0.2, text: "A quiet evening helped me reset.", now: now)
        ]

        let result = ProactiveReflectionAnalyzer.analyze(entries: entries, now: now)

        #expect(result.selectedPrompt?.priority == .high)
        #expect(result.selectedPrompt?.title.localizedCaseInsensitiveContains("regret") == true)
    }

    @Test func promptRankingIgnoresReflectedDecisions() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = makeReflectionEntry(daysAgo: 3, sentiment: -0.2, text: "I regret accepting the rushed project timeline.", now: now)
        let initial = ProactiveReflectionAnalyzer.extractDecisionMoments(from: [entry], now: now)
        let reflected = DecisionFollowUpState(
            id: initial[0].followUp.id,
            decisionID: initial[0].id,
            sourceEntryID: entry.id,
            phraseHash: initial[0].phraseHash,
            state: .reflected,
            firstSeenAt: now,
            lastPromptedAt: now,
            resolvedAt: now
        )
        let decisions = ProactiveReflectionAnalyzer.extractDecisionMoments(from: [entry], existingFollowUps: [reflected], now: now)

        let selected = ProactiveReflectionAnalyzer.selectPrompt(
            insights: [],
            decisions: decisions,
            weeklyRecap: nil,
            entries: [entry],
            now: now
        )

        #expect(selected == nil)
    }

    @Test func cadenceAnomalyWaitsForEnoughHistoryAndFlagsClearChange() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let shortHistory = (0..<6).map { makeReflectionEntry(daysAgo: $0, sentiment: 0, text: "Short note.", now: now) }
        #expect(ProactiveReflectionAnalyzer.detectCadenceAnomaly(in: shortHistory, now: now).isEmpty)

        let daysAgo = [0, 10, 20, 30, 31, 32, 33, 34, 35, 36, 37, 38]
        let entries = daysAgo.map { makeReflectionEntry(daysAgo: $0, sentiment: 0, text: "Cadence sample note.", now: now) }
        let insights = ProactiveReflectionAnalyzer.detectCadenceAnomaly(in: entries, now: now)

        #expect(!insights.isEmpty)
        #expect(insights.first?.evidence.contains { $0.role == .baseline } == true)
    }

    @Test func topicShiftAnomalyFlagsLowOverlapRecentTopicsWithEvidence() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recent = [
            makeReflectionEntry(daysAgo: 0, sentiment: 0, text: "Garden soil seedlings tomatoes compost balcony.", now: now),
            makeReflectionEntry(daysAgo: 1, sentiment: 0, text: "Seeds planter basil watering sunlight patio.", now: now),
            makeReflectionEntry(daysAgo: 2, sentiment: 0, text: "Harvest herbs pots garden gloves outdoors.", now: now)
        ]
        let baseline = (3...12).map { day in
            makeReflectionEntry(daysAgo: day, sentiment: 0, text: "Project deadline meeting sprint roadmap manager office.", now: now)
        }

        let insights = ProactiveReflectionAnalyzer.detectTopicShift(in: recent + baseline, now: now)

        #expect(!insights.isEmpty)
        #expect((insights.first?.evidence.filter { $0.role == .source }.count ?? 0) == 3)
        #expect((insights.first?.evidence.filter { $0.role == .baseline }.count ?? 0) >= 2)
    }

    @Test func repeatedThemeInsightRequiresMultipleRecentSources() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recent = [
            makeReflectionEntry(daysAgo: 0, sentiment: 0.1, text: "Garden seedlings needed more water and patient attention.", now: now),
            makeReflectionEntry(daysAgo: 1, sentiment: 0.1, text: "The garden soil and seedlings looked stronger today.", now: now),
            makeReflectionEntry(daysAgo: 2, sentiment: 0.1, text: "I checked the garden planters before work.", now: now),
            makeReflectionEntry(daysAgo: 3, sentiment: 0.1, text: "A quiet walk helped me reset.", now: now)
        ]
        let baseline = (4...12).map { day in
            makeReflectionEntry(daysAgo: day, sentiment: 0, text: "Meeting deadline office roadmap manager sprint.", now: now)
        }

        let insights = ProactiveReflectionAnalyzer.detectRepeatedTheme(in: recent + baseline, now: now)

        #expect(insights.first?.title == "A theme is taking shape")
        #expect((insights.first?.evidence.filter { $0.role == .source }.count ?? 0) >= 3)
        #expect(insights.first?.message.localizedCaseInsensitiveContains("garden") == true)
    }

    @Test func resurfacedThreadRequiresRecentAndOlderEvidence() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [
            makeReflectionEntry(daysAgo: 1, sentiment: 0.2, text: "Garden seedlings and balcony soil are back on my mind.", now: now),
            makeReflectionEntry(daysAgo: 35, sentiment: -0.1, text: "Garden soil seedlings and planter boxes felt overwhelming.", now: now),
            makeReflectionEntry(daysAgo: 42, sentiment: 0.1, text: "I wanted the garden balcony to feel calmer.", now: now)
        ]

        let insights = ProactiveReflectionAnalyzer.detectResurfacedThreads(in: entries, now: now)

        #expect(insights.first?.kind == .resurfacedThread)
        #expect(insights.first?.evidence.contains { $0.role == .source } == true)
        #expect(insights.first?.evidence.contains { $0.role == .baseline } == true)
    }

    @Test func resurfacedThreadOmitsWeakSingleOlderMatch() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [
            makeReflectionEntry(daysAgo: 1, sentiment: 0.2, text: "Garden seedlings are back on my mind.", now: now),
            makeReflectionEntry(daysAgo: 35, sentiment: -0.1, text: "Garden soil felt overwhelming.", now: now)
        ]

        let insights = ProactiveReflectionAnalyzer.detectResurfacedThreads(in: entries, now: now)

        #expect(insights.isEmpty)
    }

    @Test func topicMoodContrastShowsSameTopicDifferentFeeling() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [
            makeReflectionEntry(daysAgo: 1, sentiment: 0.55, text: "Work pressure felt lighter after the planning talk.", now: now),
            makeReflectionEntry(daysAgo: 15, sentiment: -0.45, text: "Work pressure felt heavy before the deadline.", now: now),
            makeReflectionEntry(daysAgo: 20, sentiment: -0.40, text: "Work pressure made the office feel tense.", now: now)
        ]

        let insights = ProactiveReflectionAnalyzer.detectTopicMoodContrasts(in: entries, now: now)

        #expect(insights.first?.kind == .contrast)
        #expect(insights.first?.title == "Same topic, different feeling")
        #expect(insights.first?.evidence.contains { $0.role == .baseline } == true)
    }

    @Test func quietEntityUsesBaselineEvidenceOnly() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [
            makeReflectionEntry(daysAgo: 1, sentiment: 0.0, text: "A quiet walk helped me settle after work.", now: now),
            makeReflectionEntry(daysAgo: 2, sentiment: 0.0, text: "Cooking dinner made the evening feel ordinary.", now: now),
            makeReflectionEntry(daysAgo: 20, sentiment: 0.2, text: "Dinner with Maya helped me feel less alone.", now: now),
            makeReflectionEntry(daysAgo: 30, sentiment: 0.1, text: "Maya sent a kind voice note after work.", now: now),
            makeReflectionEntry(daysAgo: 40, sentiment: 0.0, text: "The office handoff was manageable.", now: now),
            makeReflectionEntry(daysAgo: 50, sentiment: 0.0, text: "A bookshop visit felt peaceful.", now: now)
        ]

        let insights = ProactiveReflectionAnalyzer.detectQuietEntities(in: entries, now: now)

        #expect(insights.first?.kind == .quietEntity)
        #expect(insights.first?.evidence.allSatisfy { $0.role == .baseline } == true)
    }

    @Test func moodAssociationRequiresRepeatedToneEvidence() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [
            makeReflectionEntry(daysAgo: 1, sentiment: -0.6, text: "Deadline pressure made the evening heavy.", now: now),
            makeReflectionEntry(daysAgo: 3, sentiment: -0.55, text: "Deadline pressure kept me tense before sleep.", now: now),
            makeReflectionEntry(daysAgo: 5, sentiment: -0.5, text: "Deadline pressure followed me home again.", now: now),
            makeReflectionEntry(daysAgo: 8, sentiment: 0.0, text: "Cooking dinner was ordinary and quiet.", now: now),
            makeReflectionEntry(daysAgo: 10, sentiment: 0.1, text: "A walk helped me reset.", now: now),
            makeReflectionEntry(daysAgo: 12, sentiment: 0.0, text: "Reading made the room feel still.", now: now)
        ]

        let insights = ProactiveReflectionAnalyzer.detectMoodAssociations(in: entries, now: now)

        #expect(insights.first?.kind == .moodAssociation)
        #expect((insights.first?.evidence.count ?? 0) >= 3)
    }

    @Test func repeatedQuestionInsightRequiresMultipleQuestionEntries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [
            makeReflectionEntry(daysAgo: 1, sentiment: -0.1, text: "Why does deadline pressure feel so hard?", now: now),
            makeReflectionEntry(daysAgo: 3, sentiment: -0.1, text: "What would make deadline pressure easier to handle?", now: now),
            makeReflectionEntry(daysAgo: 5, sentiment: 0.0, text: "A quiet walk helped me reset.", now: now)
        ]

        let insights = ProactiveReflectionAnalyzer.detectRepeatedQuestions(in: entries, now: now)

        #expect(insights.first?.kind == .repeatedQuestion)
        #expect((insights.first?.evidence.count ?? 0) >= 2)
    }

    @Test func carryForwardWinComparesRecentLightnessToBaseline() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recent = [
            makeReflectionEntry(daysAgo: 0, sentiment: 0.55, text: "A calm walk made the day lighter.", now: now),
            makeReflectionEntry(daysAgo: 1, sentiment: 0.50, text: "Cooking helped me feel grounded.", now: now),
            makeReflectionEntry(daysAgo: 2, sentiment: 0.45, text: "I felt proud of a clear boundary.", now: now)
        ]
        let baseline = (3...8).map { day in
            makeReflectionEntry(daysAgo: day, sentiment: -0.1, text: "Work felt ordinary and a little tense.", now: now)
        }

        let insights = ProactiveReflectionAnalyzer.detectCarryForwardWins(in: recent + baseline, now: now)

        #expect(insights.first?.kind == .carryForward)
        #expect(insights.first?.evidence.contains { $0.role == .baseline } == true)
    }

    @Test func cardFeedbackTracksSavedSnoozedDismissedAndReason() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snoozedUntil = now.addingTimeInterval(3600)
        let feedback = ReflectionCardFeedback(
            insightID: "moodAssociation:deadline:45d",
            saved: true,
            dismissedAt: now,
            snoozedUntil: snoozedUntil,
            notUsefulReason: "Not relevant today",
            updatedAt: now
        )

        #expect(feedback.saved)
        #expect(feedback.feedbackKey == "moodAssociation:deadline:45d")
        #expect(feedback.isDismissed)
        #expect(feedback.isSnoozed(now: now))
        #expect(!feedback.isSnoozed(now: snoozedUntil.addingTimeInterval(1)))
        #expect(feedback.notUsefulReason == "Not relevant today")
    }

    @MainActor
    @Test func controllerFiltersDismissedCardsByStableFeedbackKey() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = ProactiveReflectionController(loadPersistedState: false)
        let feedbackKey = ProactiveReflectionAnalyzer.feedbackKey(kind: .moodAssociation, subject: "Deadline", window: "45d")
        let oldEvidenceID = UUID()
        let newEvidenceID = UUID()
        let oldInsight = ReflectionInsight(
            id: "old-\(oldEvidenceID.uuidString)",
            category: .pattern,
            priority: .high,
            title: "Deadline seems to weigh on you",
            message: "Old evidence.",
            prompt: "What support would help?",
            evidence: [],
            kind: .moodAssociation,
            feedbackKey: feedbackKey,
            createdAt: now,
            expiresAt: nil
        )
        let refreshedInsight = ReflectionInsight(
            id: "new-\(newEvidenceID.uuidString)",
            category: .pattern,
            priority: .high,
            title: "Deadline seems to weigh on you",
            message: "New evidence.",
            prompt: "What support would help?",
            evidence: [],
            kind: .moodAssociation,
            feedbackKey: feedbackKey,
            createdAt: now.addingTimeInterval(60),
            expiresAt: nil
        )

        controller.markNotUseful(oldInsight, now: now)
        let visible = controller.visibleInsightsForTesting([refreshedInsight], now: now.addingTimeInterval(120))

        #expect(visible.isEmpty)
    }

    @Test func feedbackPayloadPersistsSeparatelyFromInsightPayload() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let key = ProactiveReflectionAnalyzer.feedbackKey(kind: .quietEntity, subject: "Maya", window: "14d")
        let feedback = ReflectionCardFeedback(
            insightID: key,
            saved: false,
            dismissedAt: now,
            snoozedUntil: nil,
            notUsefulReason: "Not useful",
            updatedAt: now
        )
        let payload = ProactiveReflectionController.FeedbackPayload(version: 1, cardFeedback: [key: feedback])

        let decoded = try JSONDecoder().decode(
            ProactiveReflectionController.FeedbackPayload.self,
            from: JSONEncoder().encode(payload)
        )

        #expect(decoded.cardFeedback[key]?.notUsefulReason == "Not useful")
        #expect(decoded.cardFeedback[key]?.isDismissed == true)
    }

    @Test func analysisWorkerUsesSendableSnapshots() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [
            makeReflectionEntry(daysAgo: 1, sentiment: 0.2, text: "Garden seedlings and balcony soil are back on my mind.", now: now),
            makeReflectionEntry(daysAgo: 35, sentiment: -0.1, text: "Garden soil seedlings and planter boxes felt overwhelming.", now: now),
            makeReflectionEntry(daysAgo: 42, sentiment: 0.1, text: "I wanted the garden balcony to feel calmer.", now: now)
        ]
        let worker = ProactiveReflectionAnalysisWorker()

        let result = await worker.analyze(entries: entries, existingFollowUps: [], now: now)

        #expect(result.insights.contains { $0.kind == .resurfacedThread })
    }

    @Test func deterministicInsightsUsePatternSummaryEvidenceMode() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [
            makeReflectionEntry(daysAgo: 1, sentiment: 0.2, text: "Garden seedlings and balcony soil are back on my mind.", now: now),
            makeReflectionEntry(daysAgo: 35, sentiment: -0.1, text: "Garden soil seedlings and planter boxes felt overwhelming.", now: now),
            makeReflectionEntry(daysAgo: 42, sentiment: 0.1, text: "I wanted the garden balcony to feel calmer.", now: now)
        ]

        let insight = ProactiveReflectionAnalyzer.detectResurfacedThreads(in: entries, now: now).first

        #expect(insight?.evidenceMode == .deterministicPattern)
        #expect(insight?.feedbackKey == ProactiveReflectionAnalyzer.feedbackKey(kind: .resurfacedThread, subject: "garden", window: "28d"))
    }

    @Test func promptRankingOrderIsDecisionThenHighAnomalyThenWeekly() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = makeReflectionEntry(daysAgo: 3, sentiment: -0.2, text: "I regret accepting the rushed project timeline.", now: now)
        let decisions = ProactiveReflectionAnalyzer.extractDecisionMoments(from: [entry], now: now)
        let highAnomaly = ReflectionInsight(
            id: "high",
            category: .pattern,
            priority: .high,
            title: "High anomaly",
            message: "Pattern.",
            prompt: "Check the pattern.",
            evidence: [ProactiveReflectionAnalyzer.evidence(from: entry)],
            createdAt: now,
            expiresAt: nil
        )
        let recap = WeeklyReflectionRecap(
            id: "week",
            summary: "Weekly recap.",
            suggestedPrompt: "Weekly prompt?",
            currentWeekEntryCount: 2,
            previousWeekEntryCount: 2,
            currentWordCount: 10,
            previousWordCount: 10,
            topTopics: [],
            decisionCount: 0,
            evidence: [ProactiveReflectionAnalyzer.evidence(from: entry)],
            generatedAt: now
        )

        let decisionSelected = ProactiveReflectionAnalyzer.selectPrompt(insights: [highAnomaly], decisions: decisions, weeklyRecap: recap, entries: [entry], now: now)
        let anomalySelected = ProactiveReflectionAnalyzer.selectPrompt(insights: [highAnomaly], decisions: [], weeklyRecap: recap, entries: [entry], now: now)
        let weeklySelected = ProactiveReflectionAnalyzer.selectPrompt(insights: [], decisions: [], weeklyRecap: recap, entries: [entry], now: now)

        #expect(decisionSelected?.decisionID == decisions.first?.id)
        #expect(anomalySelected?.id == "high")
        #expect(weeklySelected?.title.localizedCaseInsensitiveContains("week") == true)
    }

    @Test func smartReminderBodyIsPrivacySafeAndFallsBack() {
        let fallback = ProactiveReflectionController.privacySafeReminderBody(for: nil)
        #expect(fallback == "Take a minute to speak about your day.")

        let sensitivePrompt = ReflectionInsight(
            id: "test",
            category: .decision,
            priority: .high,
            title: "Maya and work",
            message: "Specific private content",
            prompt: "What happened with Maya?",
            evidence: [],
            createdAt: Date(),
            expiresAt: nil
        )

        let body = ProactiveReflectionController.privacySafeReminderBody(for: sensitivePrompt)
        #expect(!body.localizedCaseInsensitiveContains("maya"))
        #expect(!body.localizedCaseInsensitiveContains("work"))
        #expect(body.localizedCaseInsensitiveContains("decision"))
    }

    @Test func smartReminderRequestUsesSingleNextNotification() {
        let manager = ReminderManager.shared
        manager.isEnabled = false
        manager.usesFridaySmartPrompts = true
        manager.reminderHour = 20
        manager.reminderMinute = 30

        let request = manager.makeReminderRequest(now: Date(timeIntervalSince1970: 1_800_000_000))
        let trigger = request.trigger as? UNCalendarNotificationTrigger

        #expect(trigger?.repeats == false)
        #expect(request.content.body == ProactiveReflectionController.cachedPrivacySafeReminderBody())
    }

    @Test func persistedPayloadDoesNotContainRawJournalSnippets() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = makeReflectionEntry(daysAgo: 0, sentiment: 0, text: "Maya private raw journal phrase", now: now)
        let insight = ReflectionInsight(
            id: "pattern",
            category: .pattern,
            priority: .medium,
            title: "Pattern",
            message: "Evidence-backed pattern.",
            prompt: "What changed?",
            evidence: [ProactiveReflectionAnalyzer.evidence(from: entry)],
            createdAt: now,
            expiresAt: nil
        )
        let payload = ProactiveReflectionController.Payload(
            version: 3,
            insights: [insight],
            decisionMoments: [],
            followUpStates: [],
            weeklyRecap: nil,
            selectedPrompt: insight,
            lastInputSignature: "signature"
        )

        let encoded = try JSONEncoder().encode(payload)
        let json = String(decoding: encoded, as: UTF8.self)

        #expect(!json.contains("Maya private raw journal phrase"))
        #expect(!json.contains("snippet"))
        #expect(json.contains(entry.id.uuidString))
    }

    @Test func expiredInsightsUseInjectedNow() {
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let insight = ReflectionInsight(
            id: "expiring",
            category: .pattern,
            priority: .medium,
            title: "Pattern",
            message: "Message",
            prompt: "Prompt",
            evidence: [],
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(60)
        )

        #expect(!insight.isExpired(now: createdAt.addingTimeInterval(30)))
        #expect(insight.isExpired(now: createdAt.addingTimeInterval(90)))
    }

    @Test func v1PayloadDecodeFailsSafelyWithoutThrowingCrash() throws {
        struct V1Payload: Codable {
            var insights: [ReflectionInsight]
        }
        let data = try JSONEncoder().encode(V1Payload(insights: []))
        let decoded = try? JSONDecoder().decode(ProactiveReflectionController.Payload.self, from: data)

        #expect(decoded == nil)
    }

    private func makeReflectionEntry(id: UUID = UUID(), daysAgo: Int, sentiment: Double, text: String, now: Date) -> ReflectionEntrySnapshot {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return ReflectionEntrySnapshot(id: id, date: date, mood: nil, text: text, sentiment: sentiment)
    }
}

// MARK: - Mood Tests

struct MoodTests {

    @Test func allMoodsHaveDisplayNames() {
        for mood in Mood.allCases {
            #expect(!mood.displayName.isEmpty, "Mood \(mood.rawValue) should have a display name")
        }
    }

    @Test func allMoodsHaveIcons() {
        for mood in Mood.allCases {
            #expect(!mood.icon.isEmpty, "Mood \(mood.rawValue) should have an icon")
        }
    }

    @Test func selectableMoodsExcludeNone() {
        let selectable = Mood.selectableMoods
        #expect(!selectable.contains(.none))
        #expect(selectable.count == Mood.allCases.count - 1)
    }

    @Test func dialMoodsUseHandoffOrder() {
        #expect(Mood.dialMoods == [.angry, .sad, .anxious, .tired, .none, .calm, .grateful, .happy, .excited])
        #expect(Mood.neutralDialIndex == 4)
    }

    @Test func dialOpensOnSavedMoodOrNeutralFallback() {
        #expect(MoodDialPersistence.openingMood(for: .sad) == .sad)
        #expect(MoodDialPersistence.openingMood(for: .none) == .none)
    }

    @Test func dialMathSnapsToNearestMood() {
        for (index, mood) in Mood.dialMoods.enumerated() {
            let rotation = MoodDialMath.rotationDegrees(for: index)
            #expect(MoodDialMath.nearestIndex(forRotationDegrees: rotation) == index)
            #expect(MoodDialMath.mood(forRotationDegrees: rotation) == mood)
        }
    }

    @Test func dialMathClampsOutsideBoundaries() {
        #expect(MoodDialMath.nearestIndex(forRotationDegrees: 999) == 0)
        #expect(MoodDialMath.nearestIndex(forRotationDegrees: -999) == Mood.dialMoods.count - 1)
        #expect(MoodDialMath.clampedRotationDegrees(999) == MoodDialMath.rotationDegrees(for: 0))
        #expect(MoodDialMath.clampedRotationDegrees(-999) == MoodDialMath.rotationDegrees(for: Mood.dialMoods.count - 1))
    }

    @Test func dialMathAddsEdgeResistanceBeyondBoundaries() {
        let first = MoodDialMath.rotationDegrees(for: 0)
        let last = MoodDialMath.rotationDegrees(for: Mood.dialMoods.count - 1)
        let resistedPastFirst = MoodDialMath.resistedRotationDegrees(first + 100)
        let resistedPastLast = MoodDialMath.resistedRotationDegrees(last - 100)

        #expect(resistedPastFirst > first)
        #expect(resistedPastFirst < first + 100)
        #expect(resistedPastLast < last)
        #expect(resistedPastLast > last - 100)
    }

    @Test func dialMetricsUseProportionalPlacement() {
        let metrics = MoodDialWheelMetrics(
            size: CGSize(width: 393, height: 852),
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        )

        #expect(metrics.dialTop >= 852 * 0.58)
        #expect(metrics.dialTop <= 852 * 0.62)
        #expect(abs(metrics.center.y - (metrics.dialTop + metrics.outerRadius)) < 0.001)
        #expect(metrics.outerRadius >= 360)
        #expect(metrics.outerRadius <= 420)
        #expect(metrics.innerRadius >= 240)
        #expect(metrics.innerRadius <= 280)
    }

    @Test func dialAssetNamesResolveForEveryMood() {
        for mood in Mood.dialMoods {
            #expect(!mood.largeMoodAssetName.isEmpty)
            #expect(!mood.miniMoodAssetName.isEmpty)
            #expect(!mood.moodGlowAssetName.isEmpty)
            #if canImport(UIKit)
            #expect(UIImage(named: mood.largeMoodAssetName) != nil, "Missing large asset for \(mood.displayName)")
            #expect(UIImage(named: mood.miniMoodAssetName) != nil, "Missing mini asset for \(mood.displayName)")
            #expect(UIImage(named: mood.moodGlowAssetName) != nil, "Missing glow asset for \(mood.displayName)")
            #endif
        }
    }

    @Test func dialDoneOnlySavesWhenDraftChanges() {
        #expect(!MoodDialPersistence.shouldSave(originalMood: .calm, draftMood: .calm))
        #expect(MoodDialPersistence.shouldSave(originalMood: .calm, draftMood: .happy))
        #expect(MoodDialPersistence.shouldSave(originalMood: .none, draftMood: .angry))
    }

    @Test func moodInitFromRawValue() {
        #expect(Mood(rawValue: "happy") == .happy)
        #expect(Mood(rawValue: "sad") == .sad)
        #expect(Mood(rawValue: "") == Mood.none)
        #expect(Mood(rawValue: "invalid") == nil)
    }

    @Test func moodIdentifiable() {
        for mood in Mood.allCases {
            #expect(mood.id == mood.rawValue)
        }
    }
}

// MARK: - Onboarding Tests

struct OnboardingResponseTests {

    @Test func defaultResponseStartsUnanswered() {
        let response = OnboardingResponse()

        #expect(response.goal == nil)
        #expect(response.painPoints.isEmpty)
        #expect(response.relatableStatements.isEmpty)
        #expect(response.reflectionFocus == nil)
        #expect(response.promptStyle == nil)
        #expect(response.faceIDChoice == .notAsked)
        #expect(response.microphoneChoice == .notAsked)
        #expect(response.speechChoice == .notAsked)
        #expect(response.firstEntryText.isEmpty)
    }

    @Test func responseCodableRoundTrip() throws {
        var response = OnboardingResponse()
        response.goal = .fridayInsights
        response.painPoints = [.typingSlow, .privacyWorry]
        response.relatableStatements = [.honestVersion, .patternWish]
        response.reflectionFocus = .relationships
        response.promptStyle = .gentle
        response.moodBaseline = .hopeful
        response.firstEntryText = "Today I noticed I needed a private place to think."
        response.faceIDChoice = .enabled
        response.microphoneChoice = .granted
        response.speechChoice = .granted

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(OnboardingResponse.self, from: data)

        #expect(decoded == response)
    }
}

// MARK: - Encryption Tests

struct EncryptionTests {

    @Test func encryptAndDecryptRoundTrip() throws {
        let originalData = Data("Hello, OffRecord AI Journal! This is a test entry.".utf8)
        let password = "SecurePassword123!"

        let encrypted = try EncryptionService.encrypt(data: originalData, password: password)
        let decrypted = try EncryptionService.decrypt(data: encrypted, password: password)

        #expect(decrypted == originalData)
    }

    @Test func encryptionProducesDifferentOutput() throws {
        let data = Data("Test data".utf8)
        let password = "password"

        let encrypted1 = try EncryptionService.encrypt(data: data, password: password)
        let encrypted2 = try EncryptionService.encrypt(data: data, password: password)

        // Different salt each time means different ciphertext
        #expect(encrypted1 != encrypted2)
    }

    @Test func decryptWithWrongPasswordFails() throws {
        let data = Data("Secret diary entry".utf8)
        let encrypted = try EncryptionService.encrypt(data: data, password: "correct")

        #expect(throws: EncryptionService.EncryptionError.self) {
            _ = try EncryptionService.decrypt(data: encrypted, password: "wrong")
        }
    }

    @Test func encryptEmptyPasswordThrows() {
        let data = Data("test".utf8)
        #expect(throws: EncryptionService.EncryptionError.invalidPassword) {
            _ = try EncryptionService.encrypt(data: data, password: "")
        }
    }

    @Test func decryptEmptyPasswordThrows() {
        let data = Data("test".utf8)
        #expect(throws: EncryptionService.EncryptionError.invalidPassword) {
            _ = try EncryptionService.decrypt(data: data, password: "")
        }
    }

    @Test func decryptInvalidDataThrows() {
        let invalidData = Data("not encrypted".utf8)
        #expect(throws: EncryptionService.EncryptionError.invalidFileFormat) {
            _ = try EncryptionService.decrypt(data: invalidData, password: "password")
        }
    }

    @Test func encryptedDataContainsMagicBytes() throws {
        let data = Data("test".utf8)
        let encrypted = try EncryptionService.encrypt(data: data, password: "password")

        // DVX1 magic bytes
        #expect(encrypted[0] == 0x44) // D
        #expect(encrypted[1] == 0x56) // V
        #expect(encrypted[2] == 0x58) // X
        #expect(encrypted[3] == 0x31) // 1
    }

    @Test func encryptLargeData() throws {
        let largeData = Data(repeating: 0xAB, count: 1_000_000) // 1MB
        let password = "strongPassword"

        let encrypted = try EncryptionService.encrypt(data: largeData, password: password)
        let decrypted = try EncryptionService.decrypt(data: encrypted, password: password)

        #expect(decrypted == largeData)
    }
}

// MARK: - EncryptionError Tests

struct EncryptionErrorTests {

    @Test func errorDescriptionsExist() {
        let errors: [EncryptionService.EncryptionError] = [
            .invalidData, .invalidPassword, .decryptionFailed, .invalidFileFormat
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
}

// MARK: - Daypart Hero Tests

struct DaypartHeroTests {

    @Test func daypartBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        #expect(DayPart.current(for: date(hour: 4, minute: 59, calendar: calendar), calendar: calendar) == .night)
        #expect(DayPart.current(for: date(hour: 5, minute: 0, calendar: calendar), calendar: calendar) == .morning)
        #expect(DayPart.current(for: date(hour: 12, minute: 0, calendar: calendar), calendar: calendar) == .afternoon)
        #expect(DayPart.current(for: date(hour: 17, minute: 0, calendar: calendar), calendar: calendar) == .evening)
        #expect(DayPart.current(for: date(hour: 21, minute: 0, calendar: calendar), calendar: calendar) == .night)
    }

    @Test func assetPrefixMappingCoversSuppliedImages() {
        #expect(DaypartHeroLibrary.assets.count == 17)
        #expect(DaypartHeroLibrary.assets.filter { $0.dayPart == .morning }.count == 4)
        #expect(DaypartHeroLibrary.assets.filter { $0.dayPart == .afternoon }.count == 5)
        #expect(DaypartHeroLibrary.assets.filter { $0.dayPart == .evening }.count == 6)
        #expect(DaypartHeroLibrary.assets.filter { $0.dayPart == .night }.count == 2)
        #expect(DaypartHeroAsset(imageName: "morning_04_sunlit_window_coffee")?.dayPart == .morning)
        #expect(DaypartHeroAsset(imageName: "not_a_daypart") == nil)
    }

    @Test func promptFilteringUsesDaypartAndUseCase() {
        let morningEmpty = DaypartHeroLibrary.prompts(dayPart: .morning, useCase: .noEntryYet)
        let morningFull = DaypartHeroLibrary.prompts(dayPart: .morning, useCase: .hasEntryAlready)

        #expect(morningEmpty.count == 6)
        #expect(morningFull.count == 3)
        #expect(morningEmpty.allSatisfy { $0.dayPart == .morning && $0.useCase == .noEntryYet })
        #expect(morningFull.allSatisfy { $0.dayPart == .morning && $0.useCase == .hasEntryAlready })
    }

    @Test func selectionAvoidsImmediatePromptAndRecentTitleRepeat() {
        let store = makeStore()
        let first = DaypartHeroLibrary.selectHero(dayPart: .evening, hasEntryToday: false, store: store, randomIndex: { _ in 0 })
        store.recordExposure(first)

        let second = DaypartHeroLibrary.selectHero(dayPart: .evening, hasEntryToday: false, store: store, randomIndex: { _ in 0 })

        #expect(second.prompt.id != first.prompt.id)
        #expect(second.prompt.title != first.prompt.title)
    }

    @Test func twoSkipsSuppressPromptForFourteenDays() {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let skipped = DaypartHeroLibrary.prompts(dayPart: .night, useCase: .noEntryYet)[0]

        store.recordSkip(promptID: skipped.id, now: now)
        #expect(!store.isSuppressed(promptID: skipped.id, now: now))

        store.recordSkip(promptID: skipped.id, now: now.addingTimeInterval(60))
        #expect(store.isSuppressed(promptID: skipped.id, now: now.addingTimeInterval(120)))

        let selected = DaypartHeroLibrary.selectHero(dayPart: .night, hasEntryToday: false, store: store, now: now.addingTimeInterval(120), randomIndex: { _ in 0 })
        #expect(selected.prompt.id != skipped.id)
    }

    @Test func longPromptResponseIncrementsAffinityAndAffectsSelectionWeight() {
        let store = makeStore()
        let boosted = DaypartHeroLibrary.prompts(dayPart: .afternoon, useCase: .noEntryYet)[0]
        store.recordPromptResponse(promptID: boosted.id, wordCount: 41)

        #expect(store.history.affinity[boosted.id] == 1)

        let selected = DaypartHeroLibrary.selectHero(dayPart: .afternoon, hasEntryToday: false, store: store, randomIndex: { _ in 1 })
        #expect(selected.prompt.id == boosted.id)
    }

    private func makeStore() -> DaypartHeroStore {
        let suiteName = "daypart-hero-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return DaypartHeroStore(defaults: defaults, key: "history")
    }

    private func date(hour: Int, minute: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 5, day: 6, hour: hour, minute: minute))!
    }
}
