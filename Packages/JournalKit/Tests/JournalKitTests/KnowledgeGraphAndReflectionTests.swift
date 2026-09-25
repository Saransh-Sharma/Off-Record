import Foundation
import Testing
@testable import KnowledgeGraphKit
@testable import ReflectionKit

struct PersonalKnowledgeGraphTests {

    @Test func addOrUpdateTracksMentionsAndSentimentEMA() {
        var graph = PersonalKnowledgeGraph()
        graph.addOrUpdate(id: "Maya", label: "Maya", type: .person, sentiment: 0.5)
        graph.addOrUpdate(id: "maya", label: "Maya", type: .person, sentiment: -0.5)

        let node = graph.nodes["maya"]
        #expect(node != nil)
        #expect(node?.mentions == 2)
        // EMA: 0.5 * 0.8 + (-0.5) * 0.2 = 0.3
        #expect(abs((node?.sentimentAssociation ?? 0) - 0.3) < 0.0001)
    }

    @Test func connectAccumulatesEdgeWeight() {
        var graph = PersonalKnowledgeGraph()
        graph.connect("Maya", to: "work", relationship: "coworker")
        graph.connect("maya", to: "Work")
        #expect(graph.edges.count == 1)
        #expect(abs(graph.edges[0].weight - 1.1) < 0.0001)
        #expect(graph.edges[0].relationship == "coworker")
    }

    @Test func importanceDecaysWithAge() {
        let recent = PersonalKnowledgeGraph.calculateImportance(mentions: 5, lastSeen: Date(), sentiment: 0)
        let old = PersonalKnowledgeGraph.calculateImportance(
            mentions: 5,
            lastSeen: Calendar.current.date(byAdding: .day, value: -60, to: Date())!,
            sentiment: 0
        )
        #expect(recent > old)
    }

    @Test func topNodesOrdersByImportance() {
        var graph = PersonalKnowledgeGraph()
        for _ in 0..<10 { graph.addOrUpdate(id: "gym", label: "Gym", type: .activity) }
        graph.addOrUpdate(id: "rarely", label: "Rarely", type: .topic)
        let top = graph.topNodes(limit: 2)
        #expect(top.first?.id == "gym")
    }

    @Test func codableRoundTrip() throws {
        var graph = PersonalKnowledgeGraph()
        graph.addOrUpdate(id: "delhi", label: "Delhi", type: .place, sentiment: 0.4)
        graph.connect("delhi", to: "family")
        let data = try JSONEncoder().encode(graph)
        let decoded = try JSONDecoder().decode(PersonalKnowledgeGraph.self, from: data)
        #expect(decoded.nodes.count == graph.nodes.count)
        #expect(decoded.edges.count == graph.edges.count)
    }
}

struct ReflectionKitTests {

    @Test func sentimentPrefersMoodSignal() {
        #expect(ReflectionSentiment.score(text: "terrible stress", mood: "happy") == 0.55)
        #expect(ReflectionSentiment.score(text: "wonderful day", mood: "angry") == -0.55)
    }

    @Test func sentimentFallsBackToKeywords() {
        #expect(ReflectionSentiment.score(text: "I feel happy and grateful and calm", mood: nil) > 0)
        #expect(ReflectionSentiment.score(text: "stress and regret and worry", mood: nil) < 0)
        #expect(ReflectionSentiment.score(text: "went to the shop", mood: nil) == 0)
    }

    @Test func entrySnapshotComputesWordCountAndSentiment() {
        let snapshot = WeeklyReflectionEntrySnapshot(
            id: UUID(),
            date: Date(),
            updatedAt: Date(),
            mood: "calm",
            text: "  A steady, calm day at the lake.  ",
            sourceType: .text
        )
        #expect(snapshot.wordCount == 7)
        #expect(snapshot.sentiment == 0.25)
        #expect(snapshot.text.hasPrefix("A steady"))
    }

    @Test func reportVisibilityRules() {
        func report(_ status: WeeklyReflectionStatus) -> WeeklyReflectionReport {
            WeeklyReflectionReport(
                id: UUID(), periodStart: Date(), periodEnd: Date(), generatedAt: Date(),
                versionNumber: 1, processingMode: .local, status: status, eligibility: .full,
                includedEntryIds: [], hiddenEntryIds: [], unavailableEntryIds: [],
                privateEntryCount: 0, inputSignature: "sig", heroSentence: "h", summary: "s",
                emotionalArc: nil, themes: [], wins: [], frictions: [], questions: [],
                savedTakeaway: nil, safetyLevel: .none, userMarkedHelpful: nil
            )
        }
        #expect(report(.ready).isVisibleOnHome)
        #expect(!report(.dismissed).isVisibleOnHome)
        #expect(!report(.superseded).isVisibleInHistory)
        #expect(report(.seen).isVisibleInHistory)
    }

    @Test func canonicalEligibilityThresholdsMatchOffRecord() {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let period = WeeklyReflectionPeriod(
            start: start,
            end: start.addingTimeInterval(7 * 24 * 60 * 60)
        )

        func snapshot(index: Int, words: Int) -> WeeklyReflectionEntrySnapshot {
            WeeklyReflectionEntrySnapshot(
                id: UUID(),
                date: calendar.date(byAdding: .day, value: index, to: start)!,
                updatedAt: start,
                mood: nil,
                text: Array(repeating: "word", count: words).joined(separator: " "),
                sourceType: .text
            )
        }

        #expect(WeeklyReflectionEligibilityEngine.evaluate(
            entries: [snapshot(index: 0, words: 149)],
            in: period
        ).kind == .empty)
        #expect(WeeklyReflectionEligibilityEngine.evaluate(
            entries: [snapshot(index: 0, words: 150)],
            in: period
        ).kind == .light)
        #expect(WeeklyReflectionEligibilityEngine.evaluate(
            entries: [
                snapshot(index: 0, words: 50),
                snapshot(index: 1, words: 50),
                snapshot(index: 2, words: 50)
            ],
            in: period
        ).kind == .full)
        #expect(WeeklyReflectionEligibilityEngine.evaluate(
            entries: [snapshot(index: 0, words: 600)],
            in: period
        ).kind == .full)
    }

    @Test func proactiveAnalyzerProducesEvidenceLinkedDecisionFollowUp() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = ReflectionEntrySnapshot(
            id: UUID(),
            date: now.addingTimeInterval(-4 * 24 * 60 * 60),
            mood: "calm",
            text: "I decided to protect two mornings for the project because focused work matters."
        )

        let result = ProactiveReflectionAnalyzer.analyze(entries: [entry], now: now)

        #expect(result.decisions.count == 1)
        #expect(result.selectedPrompt?.kind == .decisionFollowUp)
        #expect(result.selectedPrompt?.evidence.first?.entryID == entry.id)
        #expect(result.selectedPrompt?.message.contains("Friday") == false)
    }

    @Test func proactiveAnalyzerBuildsStableWeeklyRecap() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            ReflectionEntrySnapshot(
                id: UUID(),
                date: now.addingTimeInterval(-24 * 60 * 60),
                mood: "grateful",
                text: "I made progress on the launch and felt grateful for the calm collaboration."
            ),
            ReflectionEntrySnapshot(
                id: UUID(),
                date: now.addingTimeInterval(-2 * 24 * 60 * 60),
                mood: "calm",
                text: "The launch plan became clearer after a quiet block of focused work."
            )
        ]

        let first = ProactiveReflectionAnalyzer.analyze(entries: entries, now: now)
        let second = ProactiveReflectionAnalyzer.analyze(entries: entries, now: now)

        #expect(first.weeklyRecap?.id == second.weeklyRecap?.id)
        #expect(first.weeklyRecap?.evidence.count == 2)
        #expect(first.selectedPrompt?.kind == .weeklyRecap)
    }
}
