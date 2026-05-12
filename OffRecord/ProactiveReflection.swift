//
//  ProactiveReflection.swift
//  OffRecord
//
//  Local-only proactive reflection loop for Friday.
//  Derived coaching state is rebuildable from journal entries and never leaves device.
//

import CoreData
import Foundation
import os.log
import SwiftUI

private let proactiveReflectionLogger = Logger(subsystem: "com.singularity.offrecord", category: "ProactiveReflection")

// MARK: - Models

struct ReflectionEvidence: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case source
        case baseline
        case trajectory
    }

    let id: String
    let entryID: UUID
    let date: Date
    let mood: String?
    let role: Role
}

struct ReflectionInsight: Identifiable, Codable, Equatable, Sendable {
    enum Category: String, Codable, CaseIterable, Sendable {
        case pattern = "Pattern"
        case decision = "Decision"
        case weekly = "Weekly"
        case prompt = "Prompt"
    }

    enum Priority: Int, Codable, Comparable, Sendable {
        case low = 1
        case medium = 2
        case high = 3

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    let id: String
    let category: Category
    let priority: Priority
    let title: String
    let message: String
    let prompt: String
    let evidence: [ReflectionEvidence]
    let createdAt: Date
    let expiresAt: Date?
    let decisionID: String?

    init(
        id: String,
        category: Category,
        priority: Priority,
        title: String,
        message: String,
        prompt: String,
        evidence: [ReflectionEvidence],
        createdAt: Date,
        expiresAt: Date?,
        decisionID: String? = nil
    ) {
        self.id = id
        self.category = category
        self.priority = priority
        self.title = title
        self.message = message
        self.prompt = prompt
        self.evidence = evidence
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.decisionID = decisionID
    }

    func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt < now
    }
}

struct DecisionFollowUpState: Identifiable, Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case pending
        case prompted
        case reflected
        case dismissed
    }

    let id: String
    let decisionID: String
    let sourceEntryID: UUID
    let phraseHash: String
    var state: State
    let firstSeenAt: Date
    var lastPromptedAt: Date?
    var resolvedAt: Date?
}

struct DecisionMoment: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case decision
        case regret
    }

    let id: String
    let kind: Kind
    let phrase: String
    let phraseHash: String
    let entryID: UUID
    let date: Date
    let topicKeywords: [String]
    let sentiment: Double
    let followUpDueAt: Date
    var followUp: DecisionFollowUpState

    var isFollowedUp: Bool {
        followUp.state == .reflected || followUp.state == .dismissed
    }
}

struct WeeklyReflectionRecap: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let summary: String
    let suggestedPrompt: String
    let currentWeekEntryCount: Int
    let previousWeekEntryCount: Int
    let currentWordCount: Int
    let previousWordCount: Int
    let topTopics: [String]
    let decisionCount: Int
    let evidence: [ReflectionEvidence]
    let generatedAt: Date
}

struct ReflectionEntrySnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let updatedAt: Date
    let mood: String?
    let text: String
    let wordCount: Int
    let sentiment: Double

    init(id: UUID, date: Date, updatedAt: Date? = nil, mood: String?, text: String, sentiment: Double? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.date = date
        self.updatedAt = updatedAt ?? date
        self.mood = mood
        self.text = trimmed
        self.wordCount = trimmed.split { $0.isWhitespace || $0.isNewline }.count
        self.sentiment = sentiment ?? ProactiveReflectionAnalyzer.sentimentScore(text: trimmed, mood: mood)
    }

    init?(entry: DiaryEntry) {
        guard let id = entry.id else { return nil }
        let text = (entry.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let date = entry.date ?? entry.createdAt ?? Date()
        self.init(
            id: id,
            date: date,
            updatedAt: entry.updatedAt ?? date,
            mood: entry.value(forKey: "mood") as? String,
            text: text
        )
    }
}

struct ProactiveReflectionAnalysisResult: Equatable, Sendable {
    let insights: [ReflectionInsight]
    let decisions: [DecisionMoment]
    let followUpStates: [DecisionFollowUpState]
    let weeklyRecap: WeeklyReflectionRecap?
    let selectedPrompt: ReflectionInsight?
}

// MARK: - Analyzer

enum ProactiveReflectionAnalyzer {
    static let minimumAnomalyEntries = 10
    private static let currentWeekWindow: TimeInterval = 7 * 24 * 60 * 60
    private static let previousWeekWindow: TimeInterval = 14 * 24 * 60 * 60

    static func analyze(
        entries: [ReflectionEntrySnapshot],
        existingFollowUps: [DecisionFollowUpState] = [],
        now: Date = Date()
    ) -> ProactiveReflectionAnalysisResult {
        let sorted = entries.sorted { $0.date > $1.date }
        let decisions = extractDecisionMoments(from: sorted, existingFollowUps: existingFollowUps, now: now)
        let weeklyRecap = makeWeeklyRecap(from: sorted, decisions: decisions, now: now)
        let anomalyInsights = detectAnomalies(in: sorted, now: now)
        let decisionInsights = makeDecisionInsights(from: decisions, entries: sorted, now: now)
        let weeklyInsight = weeklyRecap.map { makeWeeklyInsight($0, now: now) }

        var insights = anomalyInsights + decisionInsights
        if let weeklyInsight { insights.append(weeklyInsight) }

        let selectedPrompt = selectPrompt(
            insights: insights,
            decisions: decisions,
            weeklyRecap: weeklyRecap,
            entries: sorted,
            now: now
        )

        if let selectedPrompt, !insights.contains(where: { $0.id == selectedPrompt.id }) {
            insights.append(selectedPrompt)
        }

        let activeInsights = insights
            .filter { !$0.isExpired(now: now) }
            .sorted {
                if $0.priority == $1.priority { return $0.createdAt > $1.createdAt }
                return $0.priority > $1.priority
            }

        return ProactiveReflectionAnalysisResult(
            insights: Array(activeInsights.prefix(8)),
            decisions: decisions,
            followUpStates: decisions.map(\.followUp),
            weeklyRecap: weeklyRecap,
            selectedPrompt: selectedPrompt
        )
    }

    static func detectAnomalies(in entries: [ReflectionEntrySnapshot], now: Date = Date()) -> [ReflectionInsight] {
        let sortedEntries = entries.sorted { $0.date > $1.date }
        guard sortedEntries.count >= minimumAnomalyEntries else { return [] }

        var insights: [ReflectionInsight] = []
        insights.append(contentsOf: detectSentimentAnomaly(in: sortedEntries, now: now))
        insights.append(contentsOf: detectVolumeAnomaly(in: sortedEntries, now: now))
        insights.append(contentsOf: detectTrajectoryAnomaly(in: sortedEntries, now: now))
        insights.append(contentsOf: detectCadenceAnomaly(in: sortedEntries, now: now))
        insights.append(contentsOf: detectTopicShift(in: sortedEntries, now: now))
        insights.append(contentsOf: detectRepeatedTheme(in: sortedEntries, now: now))
        return insights
    }

    static func detectCadenceAnomaly(in entries: [ReflectionEntrySnapshot], now: Date = Date()) -> [ReflectionInsight] {
        let sortedEntries = entries.sorted { $0.date > $1.date }
        guard sortedEntries.count >= minimumAnomalyEntries else { return [] }
        let recent = Array(sortedEntries.prefix(4))
        let baseline = Array(sortedEntries.dropFirst(4).prefix(10))
        guard recent.count >= 3, baseline.count >= 6 else { return [] }

        let recentAverageGap = averageGaps(in: recent)
        let baselineAverageGap = averageGaps(in: baseline)
        guard recentAverageGap > 0, baselineAverageGap > 0 else { return [] }

        let isLongSilence = recentAverageGap >= baselineAverageGap * 2.2 && recentAverageGap - baselineAverageGap >= 1.5
        let isDenseReturn = baselineAverageGap >= recentAverageGap * 2.2 && baselineAverageGap - recentAverageGap >= 1.5
        guard isLongSilence || isDenseReturn else { return [] }

        return [
            ReflectionInsight(
                id: stableID("cadence-\(recent.map(\.id.uuidString).joined())-\(isLongSilence)"),
                category: .pattern,
                priority: .medium,
                title: isLongSilence ? "Your journaling rhythm changed" : "You returned to journaling more often",
                message: isLongSilence
                ? "Friday noticed more space between recent entries than your earlier rhythm."
                : "Friday noticed your recent entries are closer together than your earlier rhythm.",
                prompt: isLongSilence ? "What made journaling harder to return to lately?" : "What brought you back to writing more often?",
                evidence: evidenceSet(source: recent.prefix(2), baseline: baseline.prefix(3)),
                createdAt: now,
                expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: now)
            )
        ]
    }

    static func detectTopicShift(in entries: [ReflectionEntrySnapshot], now: Date = Date()) -> [ReflectionInsight] {
        let sortedEntries = entries.sorted { $0.date > $1.date }
        guard sortedEntries.count >= minimumAnomalyEntries else { return [] }
        let recent = Array(sortedEntries.prefix(3))
        let baseline = Array(sortedEntries.dropFirst(3).prefix(10))
        guard recent.count == 3, baseline.count >= 6 else { return [] }

        let recentTopics = Set(topTopics(in: recent, limit: 6).map { $0.lowercased() })
        let baselineTopics = Set(topTopics(in: baseline, limit: 8).map { $0.lowercased() })
        guard recentTopics.count >= 3, baselineTopics.count >= 3 else { return [] }
        let overlap = recentTopics.intersection(baselineTopics)
        guard Double(overlap.count) / Double(max(1, recentTopics.count)) <= 0.25 else { return [] }

        return [
            ReflectionInsight(
                id: stableID("topic-shift-\(recent.map(\.id.uuidString).joined())"),
                category: .pattern,
                priority: .medium,
                title: "A newer theme is taking shape",
                message: "Friday noticed your recent entries are circling different themes than the earlier baseline.",
                prompt: "What changed around this newer thread?",
                evidence: evidenceSet(source: recent, baseline: baseline.prefix(3)),
                createdAt: now,
                expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: now)
            )
        ]
    }

    static func detectRepeatedTheme(in entries: [ReflectionEntrySnapshot], now: Date = Date()) -> [ReflectionInsight] {
        let sortedEntries = entries.sorted { $0.date > $1.date }
        guard sortedEntries.count >= minimumAnomalyEntries else { return [] }
        let recent = Array(sortedEntries.prefix(5))
        guard recent.count >= 4 else { return [] }

        var entriesByTheme: [String: [ReflectionEntrySnapshot]] = [:]
        for entry in recent {
            let themes = Set(themeKeywords(in: entry.text))
            for theme in themes {
                entriesByTheme[theme, default: []].append(entry)
            }
        }

        guard let theme = entriesByTheme
            .filter({ $0.value.count >= 3 })
            .sorted(by: {
                if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
                return $0.key < $1.key
            })
            .first else { return [] }

        return [
            ReflectionInsight(
                id: stableID("repeated-theme-\(theme.key)-\(theme.value.map(\.id.uuidString).joined())"),
                category: .pattern,
                priority: .medium,
                title: "A theme is taking shape",
                message: "Friday noticed \(theme.key.capitalized) coming up across several recent entries.",
                prompt: "What is this thread asking you to notice?",
                evidence: theme.value.prefix(4).map { evidence(from: $0, role: .source) },
                createdAt: now,
                expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: now)
            )
        ]
    }

    static func extractDecisionMoments(
        from entries: [ReflectionEntrySnapshot],
        existingFollowUps: [DecisionFollowUpState] = [],
        now: Date = Date()
    ) -> [DecisionMoment] {
        var followUpByKey: [String: DecisionFollowUpState] = [:]
        for followUp in existingFollowUps {
            followUpByKey["\(followUp.sourceEntryID.uuidString)-\(followUp.phraseHash)"] = followUp
        }

        return entries.flatMap { entry in
            sentences(in: entry.text).compactMap { sentence -> DecisionMoment? in
                let lower = sentence.lowercased()
                let kind: DecisionMoment.Kind
                if containsAny(lower, ["i regret", "i wish", "i should have", "i shouldn't have", "i should not have"]) {
                    kind = .regret
                } else if containsAny(lower, ["i decided", "i chose", "i choose", "i picked", "i committed to"]) {
                    kind = .decision
                } else {
                    return nil
                }

                let phrase = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                guard phrase.split(separator: " ").count >= 4 else { return nil }
                let phraseHash = stableID(phrase.lowercased())
                let decisionID = stableID("\(entry.id)-\(phraseHash)")
                let key = "\(entry.id.uuidString)-\(phraseHash)"
                let existing = followUpByKey[key]
                let followUp = existing ?? DecisionFollowUpState(
                    id: stableID("follow-up-\(decisionID)"),
                    decisionID: decisionID,
                    sourceEntryID: entry.id,
                    phraseHash: phraseHash,
                    state: .pending,
                    firstSeenAt: now,
                    lastPromptedAt: nil,
                    resolvedAt: nil
                )

                return DecisionMoment(
                    id: decisionID,
                    kind: kind,
                    phrase: phrase,
                    phraseHash: phraseHash,
                    entryID: entry.id,
                    date: entry.date,
                    topicKeywords: topicKeywords(in: phrase, limit: 4),
                    sentiment: entry.sentiment,
                    followUpDueAt: Calendar.current.date(byAdding: .day, value: 2, to: entry.date) ?? entry.date,
                    followUp: followUp
                )
            }
        }
    }

    static func makeWeeklyRecap(from entries: [ReflectionEntrySnapshot], decisions: [DecisionMoment], now: Date = Date()) -> WeeklyReflectionRecap? {
        let currentWeek = entries.filter { now.timeIntervalSince($0.date) >= 0 && now.timeIntervalSince($0.date) <= currentWeekWindow }
        let previousWeek = entries.filter {
            let age = now.timeIntervalSince($0.date)
            return age > currentWeekWindow && age <= previousWeekWindow
        }

        guard currentWeek.count >= 2 else { return nil }
        let currentWords = currentWeek.reduce(0) { $0 + $1.wordCount }
        let previousWords = previousWeek.reduce(0) { $0 + $1.wordCount }
        let currentMood = average(currentWeek.map(\.sentiment))
        let previousMood = average(previousWeek.map(\.sentiment))
        let moodDelta = currentMood - previousMood
        let topics = topTopics(in: currentWeek, limit: 4)
        let weekDecisions = decisions.filter { now.timeIntervalSince($0.date) <= currentWeekWindow }

        let moodLine: String
        if previousWeek.isEmpty {
            moodLine = "Friday has enough from this week to start a gentle recap."
        } else if moodDelta > 0.12 {
            moodLine = "This week reads a little lighter than last week."
        } else if moodDelta < -0.12 {
            moodLine = "This week reads a little heavier than last week."
        } else {
            moodLine = "Your emotional tone stayed fairly steady this week."
        }

        let volumeLine: String
        if previousWeek.isEmpty {
            volumeLine = "You wrote \(currentWeek.count) entries and \(currentWords) words."
        } else if currentWords > previousWords {
            volumeLine = "You wrote more than last week."
        } else if currentWords < previousWords {
            volumeLine = "You wrote less than last week."
        } else {
            volumeLine = "Your writing volume matched last week."
        }

        let decisionLine = weekDecisions.isEmpty ? "" : " Friday also noticed \(weekDecisions.count) decision or regret moment\(weekDecisions.count == 1 ? "" : "s")."
        let summary = "\(moodLine) \(volumeLine)\(decisionLine)"
        let prompt = weekDecisions.isEmpty
        ? "What pattern from this week do you want to carry forward?"
        : "Which decision from this week still deserves attention?"

        return WeeklyReflectionRecap(
            id: stableID("weekly-\(Calendar.current.component(.weekOfYear, from: now))-\(Calendar.current.component(.yearForWeekOfYear, from: now))"),
            summary: summary,
            suggestedPrompt: prompt,
            currentWeekEntryCount: currentWeek.count,
            previousWeekEntryCount: previousWeek.count,
            currentWordCount: currentWords,
            previousWordCount: previousWords,
            topTopics: topics,
            decisionCount: weekDecisions.count,
            evidence: Array(currentWeek.prefix(3)).map { evidence(from: $0, role: .source) },
            generatedAt: now
        )
    }

    static func selectPrompt(
        insights: [ReflectionInsight],
        decisions: [DecisionMoment],
        weeklyRecap: WeeklyReflectionRecap?,
        entries: [ReflectionEntrySnapshot],
        now: Date = Date()
    ) -> ReflectionInsight? {
        if let unresolved = decisions
            .filter({ $0.followUp.state == .pending && $0.followUpDueAt <= now })
            .sorted(by: { $0.date > $1.date })
            .first,
           let entry = entries.first(where: { $0.id == unresolved.entryID }) {
            return ReflectionInsight(
                id: stableID("decision-prompt-\(unresolved.id)"),
                category: .prompt,
                priority: .high,
                title: unresolved.kind == .regret ? "A regret may need a softer second look" : "A decision is ready for a check-in",
                message: "Friday noticed a recent \(unresolved.kind == .regret ? "regret" : "decision") that may be worth revisiting.",
                prompt: unresolved.kind == .regret ? "What would you do differently with what you know now?" : "How does that choice feel after a little distance?",
                evidence: [evidence(from: entry, role: .source)],
                createdAt: now,
                expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: now),
                decisionID: unresolved.id
            )
        }

        if let high = insights.filter({ $0.priority == .high }).sorted(by: { $0.createdAt > $1.createdAt }).first {
            return high
        }

        if let weeklyRecap {
            return ReflectionInsight(
                id: stableID("weekly-prompt-\(weeklyRecap.id)"),
                category: .prompt,
                priority: .medium,
                title: "Your week has a thread worth naming",
                message: "Friday prepared a gentle weekly reflection from your recent entries.",
                prompt: weeklyRecap.suggestedPrompt,
                evidence: weeklyRecap.evidence,
                createdAt: now,
                expiresAt: Calendar.current.date(byAdding: .day, value: 3, to: now)
            )
        }

        return nil
    }

    static func sentimentScore(text: String, mood: String?) -> Double {
        if let mood {
            switch mood.lowercased() {
            case "happy", "excited", "grateful": return 0.55
            case "calm": return 0.25
            case "okay", "neutral": return 0.0
            case "tired": return -0.18
            case "sad", "anxious": return -0.45
            case "angry": return -0.55
            default: break
            }
        }

        let lower = text.lowercased()
        let positive = ["happy", "calm", "proud", "grateful", "lighter", "good", "better", "relieved", "peaceful"]
        let negative = ["stress", "anxious", "sad", "angry", "crushed", "regret", "worried", "tense", "heavy", "tired"]
        let positiveCount = positive.filter { lower.contains($0) }.count
        let negativeCount = negative.filter { lower.contains($0) }.count
        let total = max(1, positiveCount + negativeCount)
        return max(-0.8, min(0.8, Double(positiveCount - negativeCount) / Double(total)))
    }

    static func evidence(from entry: ReflectionEntrySnapshot, role: ReflectionEvidence.Role = .source) -> ReflectionEvidence {
        ReflectionEvidence(
            id: stableID("\(entry.id)-\(entry.date.timeIntervalSince1970)-\(role.rawValue)"),
            entryID: entry.id,
            date: entry.date,
            mood: entry.mood,
            role: role
        )
    }

    static func snippet(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard collapsed.count > 150 else { return collapsed }
        return String(collapsed.prefix(147)) + "..."
    }

    static func stableID(_ value: String) -> String {
        TextSignals.hash(value).prefix(16).description
    }

    private static func detectSentimentAnomaly(in sortedEntries: [ReflectionEntrySnapshot], now: Date) -> [ReflectionInsight] {
        let recentCandidates = Array(sortedEntries.prefix(3))
        for latest in recentCandidates {
            let baseline = sortedEntries.filter { $0.id != latest.id }.prefix(30)
            guard baseline.count >= minimumAnomalyEntries - 1 else { continue }
            let baselineSentiments = baseline.map(\.sentiment)
            let sentimentDelta = latest.sentiment - average(baselineSentiments)
            let sentimentZScore = zScore(value: latest.sentiment, baseline: baselineSentiments)
            guard abs(sentimentZScore ?? 0) >= 1.8 || abs(sentimentDelta) >= 0.35 else { continue }
            let heavier = sentimentDelta < 0
            return [
                ReflectionInsight(
                    id: stableID("sentiment-\(latest.id)-\(heavier)"),
                    category: .pattern,
                    priority: .high,
                    title: heavier ? "This entry felt heavier than usual" : "This entry felt lighter than usual",
                    message: heavier
                    ? "Friday noticed this entry's tone sits outside your recent baseline."
                    : "Friday noticed this entry's tone is lighter than your recent baseline.",
                    prompt: heavier ? "What changed the emotional weight of this entry?" : "What helped this entry feel lighter?",
                    evidence: evidenceSet(source: [latest], baseline: baseline.prefix(3)),
                    createdAt: now,
                    expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: now)
                )
            ]
        }
        return []
    }

    private static func detectVolumeAnomaly(in sortedEntries: [ReflectionEntrySnapshot], now: Date) -> [ReflectionInsight] {
        let latest = sortedEntries[0]
        let baseline = Array(sortedEntries.dropFirst().prefix(30))
        let baselineWordCounts = baseline.map { Double($0.wordCount) }
        let wordZScore = zScore(value: Double(latest.wordCount), baseline: baselineWordCounts)
        let baselineAverage = average(baselineWordCounts)
        let absoluteDelta = Double(latest.wordCount) - baselineAverage
        let flatBaselineOutlier = wordZScore == nil && abs(absoluteDelta) >= max(35, baselineAverage * 1.8)
        guard abs(wordZScore ?? 0) >= 1.8 || flatBaselineOutlier else {
            return []
        }

        let more = (wordZScore ?? absoluteDelta) > 0
        return [
            ReflectionInsight(
                id: stableID("volume-\(latest.id)-\(more)"),
                category: .pattern,
                priority: .medium,
                title: more ? "You had more to say than usual" : "You wrote less than usual",
                message: more
                ? "Friday noticed this entry was longer than your recent baseline."
                : "Friday noticed this entry was shorter than your recent baseline.",
                prompt: more ? "What needed the extra space today?" : "Was there something you held back today?",
                evidence: evidenceSet(source: [latest], baseline: baseline.prefix(3)),
                createdAt: now,
                expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: now)
            )
        ]
    }

    private static func detectTrajectoryAnomaly(in sortedEntries: [ReflectionEntrySnapshot], now: Date) -> [ReflectionInsight] {
        let recent = Array(sortedEntries.prefix(5)).reversed()
        guard recent.count == 5, recent.map(\.sentiment).isStrictlyDescending else { return [] }
        return [
            ReflectionInsight(
                id: stableID("trajectory-\(recent.map(\.id.uuidString).joined())"),
                category: .pattern,
                priority: .high,
                title: "A downward mood pattern is forming",
                message: "Friday noticed the last few entries have each felt a little heavier.",
                prompt: "What support would make the next few days easier?",
                evidence: recent.map { evidence(from: $0, role: .trajectory) },
                createdAt: now,
                expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: now)
            )
        ]
    }

    private static func makeDecisionInsights(from decisions: [DecisionMoment], entries: [ReflectionEntrySnapshot], now: Date) -> [ReflectionInsight] {
        decisions
            .filter { now.timeIntervalSince($0.date) <= currentWeekWindow && $0.followUp.state != .dismissed }
            .prefix(2)
            .compactMap { decision in
                guard let entry = entries.first(where: { $0.id == decision.entryID }) else { return nil }
                return ReflectionInsight(
                    id: stableID("decision-\(decision.id)"),
                    category: .decision,
                    priority: decision.kind == .regret ? .high : .medium,
                    title: decision.kind == .regret ? "Friday noticed a regret thread" : "Friday noticed a decision point",
                    message: decision.kind == .regret
                    ? "There is a recent moment where you seemed to be replaying a choice."
                    : "There is a recent choice that may be worth tracking after a little distance.",
                    prompt: decision.kind == .regret ? "What would a kinder next step look like from here?" : "What outcome will tell you this was the right choice?",
                    evidence: [evidence(from: entry, role: .source)],
                    createdAt: now,
                    expiresAt: Calendar.current.date(byAdding: .day, value: 10, to: now),
                    decisionID: decision.id
                )
            }
    }

    private static func makeWeeklyInsight(_ recap: WeeklyReflectionRecap, now: Date) -> ReflectionInsight {
        ReflectionInsight(
            id: stableID("weekly-insight-\(recap.id)"),
            category: .weekly,
            priority: .medium,
            title: "Your weekly pattern recap is ready",
            message: recap.summary,
            prompt: recap.suggestedPrompt,
            evidence: recap.evidence,
            createdAt: now,
            expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: now)
        )
    }

    private static func evidenceSet<S: Sequence, B: Sequence>(
        source: S,
        baseline: B
    ) -> [ReflectionEvidence] where S.Element == ReflectionEntrySnapshot, B.Element == ReflectionEntrySnapshot {
        source.map { evidence(from: $0, role: .source) } + baseline.map { evidence(from: $0, role: .baseline) }
    }

    private static func zScore(value: Double, baseline: [Double]) -> Double? {
        guard baseline.count >= 3 else { return nil }
        let mean = average(baseline)
        let variance = baseline.reduce(0) { $0 + pow($1 - mean, 2) } / Double(baseline.count)
        let stdDev = sqrt(variance)
        guard stdDev > 0.0001 else { return nil }
        return (value - mean) / stdDev
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func averageGaps(in entries: [ReflectionEntrySnapshot]) -> Double {
        let ascending = entries.sorted { $0.date < $1.date }
        guard ascending.count > 1 else { return 0 }
        let gaps = zip(ascending.dropFirst(), ascending).map { newer, older in
            newer.date.timeIntervalSince(older.date) / (24 * 60 * 60)
        }
        return average(gaps)
    }

    private static func sentences(in text: String) -> [String] {
        text.split(whereSeparator: { ".!?\n".contains($0) }).map(String.init)
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func topicKeywords(in text: String, limit: Int) -> [String] {
        let words = text
            .lowercased()
            .split { $0.isWhitespace || $0.isPunctuation || $0.isNewline }
            .map(String.init)
            .filter { $0.count > 4 && !ReflectionStopWords.words.contains($0) }
        return Array(NSOrderedSet(array: words).compactMap { $0 as? String }.prefix(limit))
    }

    private static func themeKeywords(in text: String) -> [String] {
        let topics = topicKeywords(in: text, limit: 12)
        let entities = TextSignals.extractEntities(from: text)
            .map { $0.lowercased() }
            .filter { $0.count > 2 && !ReflectionStopWords.words.contains($0) }
        return Array(NSOrderedSet(array: topics + entities).compactMap { $0 as? String })
    }

    private static func topTopics(in entries: [ReflectionEntrySnapshot], limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for entry in entries {
            topicKeywords(in: entry.text, limit: 12).forEach { counts[$0, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map { $0.key.capitalized }
    }
}

private enum ReflectionStopWords {
    static let words: Set<String> = [
        "about", "after", "again", "because", "before", "could", "every", "everyone",
        "feels", "going", "their", "there", "these", "thing", "things", "today",
        "tomorrow", "would", "should", "really", "still", "where", "which", "while",
        "project", "entry", "journal", "friday"
    ]
}

private extension Array where Element == Double {
    var isStrictlyDescending: Bool {
        guard count > 1 else { return false }
        for index in 1..<count where self[index] >= self[index - 1] {
            return false
        }
        return true
    }
}

// MARK: - Controller

final class ProactiveReflectionController: ObservableObject {
    static let shared = ProactiveReflectionController()

    @Published private(set) var insights: [ReflectionInsight] = []
    @Published private(set) var decisionMoments: [DecisionMoment] = []
    @Published private(set) var followUpStates: [DecisionFollowUpState] = []
    @Published private(set) var weeklyRecap: WeeklyReflectionRecap?
    @Published private(set) var selectedPrompt: ReflectionInsight?

    private let stateType = "proactive_reflection_loop"
    private let debounceInterval: TimeInterval = 1.5
    private var lastInputSignature: String?
    private var lastRefreshAt: Date?

    private init() {
        load()
    }

    func refreshIfNeeded(entries: [DiaryEntry], now: Date = Date(), force: Bool = false) {
        let snapshots = entries.compactMap(ReflectionEntrySnapshot.init(entry:))
        let signature = inputSignature(for: snapshots)
        if !force, signature == lastInputSignature, let lastRefreshAt, now.timeIntervalSince(lastRefreshAt) < debounceInterval {
            return
        }
        refresh(snapshots: snapshots, signature: signature, now: now)
    }

    func refresh(entries: [DiaryEntry], now: Date = Date()) {
        let snapshots = entries.compactMap(ReflectionEntrySnapshot.init(entry:))
        refresh(snapshots: snapshots, signature: inputSignature(for: snapshots), now: now)
    }

    func markPrompted(_ insight: ReflectionInsight, now: Date = Date()) {
        guard let decisionID = insight.decisionID else { return }
        updateFollowUp(decisionID: decisionID, state: .prompted, now: now)
    }

    func markReflected(_ insight: ReflectionInsight, now: Date = Date()) {
        guard let decisionID = insight.decisionID else { return }
        updateFollowUp(decisionID: decisionID, state: .reflected, now: now)
    }

    func privacySafeReminderBody() -> String {
        Self.privacySafeReminderBody(for: selectedPrompt)
    }

    static func privacySafeReminderBody(for prompt: ReflectionInsight?) -> String {
        guard let prompt else {
            return "Take a minute to speak about your day."
        }

        switch prompt.category {
        case .decision:
            return "Friday has a decision check-in for today."
        case .weekly:
            return "Friday has a weekly reflection ready."
        case .pattern:
            return "A pattern is worth checking in on today."
        case .prompt:
            return prompt.decisionID == nil ? "Friday has a reflection for tonight." : "Friday has a decision check-in for today."
        }
    }

    struct Payload: Codable {
        var version: Int
        var insights: [ReflectionInsight]
        var decisionMoments: [DecisionMoment]
        var followUpStates: [DecisionFollowUpState]
        var weeklyRecap: WeeklyReflectionRecap?
        var selectedPrompt: ReflectionInsight?
        var lastInputSignature: String?
    }

    private func refresh(snapshots: [ReflectionEntrySnapshot], signature: String, now: Date) {
        let result = ProactiveReflectionAnalyzer.analyze(entries: snapshots, existingFollowUps: followUpStates, now: now)
        insights = result.insights
        decisionMoments = result.decisions
        followUpStates = result.followUpStates
        weeklyRecap = result.weeklyRecap
        selectedPrompt = result.selectedPrompt
        lastInputSignature = signature
        lastRefreshAt = now
        save()
        ReminderManager.shared.reconcileScheduleIfNeeded()
    }

    private func updateFollowUp(decisionID: String, state: DecisionFollowUpState.State, now: Date) {
        guard let index = followUpStates.firstIndex(where: { $0.decisionID == decisionID }) else { return }
        followUpStates[index].state = state
        if state == .prompted {
            followUpStates[index].lastPromptedAt = now
        }
        if state == .reflected || state == .dismissed {
            followUpStates[index].resolvedAt = now
        }
        decisionMoments = decisionMoments.map { decision in
            guard decision.id == decisionID else { return decision }
            var updated = decision
            updated.followUp = followUpStates[index]
            return updated
        }
        save()
        ReminderManager.shared.reconcileScheduleIfNeeded()
    }

    private func save() {
        let payload = Payload(
            version: 2,
            insights: insights,
            decisionMoments: decisionMoments,
            followUpStates: followUpStates,
            weeklyRecap: weeklyRecap,
            selectedPrompt: selectedPrompt,
            lastInputSignature: lastInputSignature
        )
        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            proactiveReflectionLogger.error("Failed to encode proactive reflection payload: \(error.localizedDescription, privacy: .public)")
            return
        }

        let context = PersistenceController.shared.container.newBackgroundContext()
        let stateType = stateType
        context.perform {
            do {
                let request = NSFetchRequest<AIState>(entityName: "AIState")
                request.predicate = NSPredicate(format: "type == %@", stateType)
                request.fetchLimit = 1
                let existing = try context.fetch(request).first
                let state = existing ?? AIState(context: context)
                if existing == nil {
                    state.id = UUID()
                    state.type = stateType
                }
                state.payload = data
                state.updatedAt = Date()
                try context.save()
            } catch {
                proactiveReflectionLogger.error("Failed to save proactive reflection payload: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func load() {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<AIState>(entityName: "AIState")
        request.predicate = NSPredicate(format: "type == %@", stateType)
        request.fetchLimit = 1
        guard let state = try? context.fetch(request).first, let data = state.payload else { return }

        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard payload.version == 2 else { return }
            insights = payload.insights
            decisionMoments = payload.decisionMoments
            followUpStates = payload.followUpStates
            weeklyRecap = payload.weeklyRecap
            selectedPrompt = payload.selectedPrompt
            lastInputSignature = payload.lastInputSignature
        } catch {
            proactiveReflectionLogger.notice("Ignoring old proactive reflection payload; it will rebuild on refresh.")
        }
    }

    private func inputSignature(for snapshots: [ReflectionEntrySnapshot]) -> String {
        let newest = snapshots.max { $0.updatedAt < $1.updatedAt }
        return [
            "\(snapshots.count)",
            newest?.id.uuidString ?? "none",
            "\(newest?.date.timeIntervalSince1970 ?? 0)",
            "\(newest?.updatedAt.timeIntervalSince1970 ?? 0)"
        ].joined(separator: "|")
    }
}

// MARK: - Friday UI

struct ProactiveReflectionSection: View {
    let entries: [DiaryEntry]
    var onWritePrompt: ((ReflectionInsight) -> Void)?
    @ObservedObject private var controller = ProactiveReflectionController.shared
    @State private var selectedInsight: ReflectionInsight?

    var body: some View {
        Group {
            if !controller.insights.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        FridayMascotView(pose: .thinking, size: 34)
                        Text("Friday noticed")
                            .font(.headline)
                            .foregroundColor(OffRecordColor.textHeading)
                            .accessibilityIdentifier("proactiveReflection.section")
                        Spacer()
                    }

                    ForEach(controller.insights.prefix(4)) { insight in
                        Button {
                            selectedInsight = insight
                            if insight.decisionID != nil {
                                controller.markPrompted(insight)
                            }
                            HapticManager.shared.selectionChanged()
                        } label: {
                            ReflectionInsightCard(insight: insight)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("proactiveReflection.card.\(insight.category.rawValue.lowercased())")
                        .accessibilityLabel("Reflect on \(insight.category.rawValue.lowercased()). \(insight.evidence.count) evidence \(insight.evidence.count == 1 ? "entry" : "entries").")
                        .accessibilityHint("Opens evidence and suggested prompt.")
                    }
                }
            }
        }
        .onAppear { controller.refreshIfNeeded(entries: entries) }
        .onChange(of: entries.count) { _, _ in controller.refreshIfNeeded(entries: entries) }
        .sheet(item: $selectedInsight) { insight in
            ReflectionInsightDetailView(
                insight: insight,
                entries: entries,
                onWritePrompt: onWritePrompt
            )
            .presentationDetents([.medium, .large])
        }
    }
}

private struct ReflectionInsightCard: View {
    let insight: ReflectionInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(style.fill)
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(style.foreground)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(insight.category.rawValue)
                            .font(OffRecordTypography.labelSmall)
                            .foregroundColor(style.foreground)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(style.fill))
                            .overlay(Capsule().stroke(style.border, lineWidth: 1))

                        if !insight.evidence.isEmpty {
                            Label("\(insight.evidence.count)", systemImage: "quote.bubble")
                                .font(OffRecordTypography.labelSmall)
                                .foregroundColor(OffRecordColor.textSecondary)
                        }
                    }

                    Text(insight.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(OffRecordColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(insight.message)
                        .font(.caption)
                        .foregroundColor(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(OffRecordColor.textTertiary)
            }

            Text("Reflect on this")
                .font(OffRecordTypography.labelSmall)
                .foregroundColor(OffRecordColor.textLavender)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceLavender)
    }

    private var icon: String {
        switch insight.category {
        case .pattern: return "waveform.path.ecg"
        case .decision: return "arrow.triangle.branch"
        case .weekly: return "calendar.badge.clock"
        case .prompt: return "sparkles"
        }
    }

    private var style: OffRecordReadableTintStyle {
        switch insight.category {
        case .pattern: return .growth
        case .decision: return .journal
        case .weekly: return .export
        case .prompt: return .friday
        }
    }
}

private struct ReflectionInsightDetailView: View {
    let insight: ReflectionInsight
    let entries: [DiaryEntry]
    var onWritePrompt: ((ReflectionInsight) -> Void)?
    @ObservedObject private var controller = ProactiveReflectionController.shared
    @Environment(\.dismiss) private var dismiss

    private var sourceEvidence: [ReflectionEvidence] {
        insight.evidence.filter { $0.role == .source || $0.role == .trajectory }
    }

    private var baselineEvidence: [ReflectionEvidence] {
        insight.evidence.filter { $0.role == .baseline }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(insight.category.rawValue)
                            .font(OffRecordTypography.labelSmall)
                            .foregroundColor(OffRecordColor.textLavender)
                            .accessibilityIdentifier("proactiveReflection.detail")
                        Text(insight.title)
                            .font(OffRecordTypography.titleLarge)
                            .foregroundColor(OffRecordColor.textHeading)
                        Text(insight.message)
                            .font(OffRecordTypography.bodyMedium)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Prompt", systemImage: "sparkles")
                            .font(.headline)
                            .foregroundColor(OffRecordColor.textHeading)
                        Text(insight.prompt)
                            .font(OffRecordTypography.bodyLarge)
                            .foregroundColor(OffRecordColor.textPrimary)
                    }
                    .padding()
                    .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfacePeach)

                    HStack(spacing: 10) {
                        if let onWritePrompt {
                            Button {
                                controller.markPrompted(insight)
                                onWritePrompt(insight)
                                dismiss()
                            } label: {
                                Label("Write from prompt", systemImage: "square.and.pencil")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if insight.decisionID != nil {
                            Button {
                                controller.markReflected(insight)
                                dismiss()
                            } label: {
                                Label("Mark reflected", systemImage: "checkmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("proactiveReflection.markReflected")
                        }
                    }

                    evidenceSection(title: "Source entry", evidence: sourceEvidence)
                    evidenceSection(title: "Baseline entries", evidence: baselineEvidence)

                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(OffRecordColor.textSage)
                        Text("Generated on-device from your journal.")
                            .font(.caption)
                            .foregroundColor(OffRecordColor.textSage)
                    }
                }
                .padding(OffRecordSpacing.xxl)
            }
            .background(OffRecordColor.appBackgroundGradient.ignoresSafeArea())
            .navigationTitle("Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func evidenceSection(title: String, evidence: [ReflectionEvidence]) -> some View {
        if !evidence.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: "quote.bubble.fill")
                    .font(.headline)
                    .foregroundColor(OffRecordColor.textHeading)
                    .accessibilityIdentifier(title == "Source entry" ? "proactiveReflection.evidence.source" : "proactiveReflection.evidence.baseline")

                ForEach(evidence) { evidence in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(evidence.date, style: .date)
                            .font(OffRecordTypography.labelSmall)
                            .foregroundColor(OffRecordColor.textSecondary)
                        HStack(spacing: 6) {
                            Text(roleLabel(for: evidence.role))
                                .font(OffRecordTypography.labelSmall)
                                .foregroundColor(OffRecordColor.textLavender)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(OffRecordColor.backgroundLavenderTint))
                            if let mood = evidence.mood, !mood.isEmpty {
                                Text(mood.capitalized)
                                    .font(OffRecordTypography.labelSmall)
                                    .foregroundColor(OffRecordColor.textSage)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(OffRecordColor.backgroundSageTint))
                            }
                        }
                        Text(snippet(for: evidence))
                            .font(OffRecordTypography.bodySmall)
                            .foregroundColor(OffRecordColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous)
                            .fill(OffRecordColor.surfaceWarm)
                    )
                }
            }
        }
    }

    private func roleLabel(for role: ReflectionEvidence.Role) -> String {
        switch role {
        case .source: return "Source"
        case .baseline: return "Baseline"
        case .trajectory: return "Trend"
        }
    }

    private func snippet(for evidence: ReflectionEvidence) -> String {
        guard let entry = entries.first(where: { $0.id == evidence.entryID }),
              let text = entry.text,
              !text.isEmpty else {
            return "Entry text is unavailable."
        }
        return ProactiveReflectionAnalyzer.snippet(text)
    }
}

// MARK: - Today / Insights UI

struct ProactiveReflectionPromptCard: View {
    let entries: [DiaryEntry]
    let hasEntryToday: Bool
    let onWrite: (ReflectionInsight) -> Void
    @ObservedObject private var controller = ProactiveReflectionController.shared

    var body: some View {
        Group {
            if !hasEntryToday, let prompt = controller.selectedPrompt, prompt.priority == .high {
                Button {
                    controller.markPrompted(prompt)
                    onWrite(prompt)
                    HapticManager.shared.selectionChanged()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(OffRecordColor.backgroundLavenderTint)
                                .frame(width: 38, height: 38)
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(OffRecordColor.textLavender)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(prompt.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(OffRecordColor.textHeading)
                            Text(prompt.prompt)
                                .font(.caption)
                                .foregroundColor(OffRecordColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Private • On your device")
                                .font(OffRecordTypography.labelSmall)
                                .foregroundColor(OffRecordColor.textSage)
                        }

                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(OffRecordColor.textLavender)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceBlush)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("proactiveReflection.todayPrompt")
                .accessibilityLabel("Friday reflection prompt. \(prompt.evidence.count) evidence \(prompt.evidence.count == 1 ? "entry" : "entries").")
                .accessibilityHint("Opens a note with this prompt.")
            }
        }
        .onAppear { controller.refreshIfNeeded(entries: entries) }
    }
}

struct ProactiveWeeklyReflectionCard: View {
    let entries: [DiaryEntry]
    @ObservedObject private var controller = ProactiveReflectionController.shared

    var body: some View {
        Group {
            if let recap = controller.weeklyRecap {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(OffRecordColor.textAqua)
                        Text("Weekly reflection")
                            .font(.headline)
                            .foregroundColor(OffRecordColor.textHeading)
                        Spacer()
                    }

                    Text(recap.summary)
                        .font(.subheadline)
                        .foregroundColor(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !recap.topTopics.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(recap.topTopics, id: \.self) { topic in
                                Text(topic)
                                    .font(OffRecordTypography.labelSmall)
                                    .foregroundColor(OffRecordColor.textAqua)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(OffRecordColor.surfaceMint))
                            }
                        }
                    }

                    Text(recap.suggestedPrompt)
                        .font(OffRecordTypography.bodySmall)
                        .foregroundColor(OffRecordColor.textPrimary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous)
                                .fill(OffRecordColor.surfaceWarm)
                        )
                }
                .padding()
                .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceMint)
                .accessibilityIdentifier("proactiveReflection.weeklyRecap")
            }
        }
        .onAppear { controller.refreshIfNeeded(entries: entries) }
        .onChange(of: entries.count) { _, _ in controller.refreshIfNeeded(entries: entries) }
    }
}
