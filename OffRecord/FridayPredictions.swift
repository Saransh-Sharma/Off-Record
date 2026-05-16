//
//  FridayPredictions.swift
//  OffRecord
//
//  "Friday noticed..." — proactive observations based on journal patterns.
//  Uses FridayAssistantEngine data to anticipate moods, surface observations,
//  and give users a reason to open the app even when they don't feel like journaling.
//
//  All predictions are generated on-device from existing data.
//

import Foundation
import SwiftUI

// MARK: - Prediction Model

struct FridayPrediction: Identifiable {
    let id = UUID()
    let message: String
    let detail: String?
    let icon: String
    let tint: Color
    let category: Category

    enum Category: String {
        case mood          // Mood-based predictions
        case people        // Relationship observations
        case pattern       // Behavioral pattern alerts
        case nudge         // Gentle engagement nudges
        case growth        // Growth/change observations
    }
}

// MARK: - Prediction Engine

@MainActor
struct FridayPredictionEngine {

    /// Generate up to 3 relevant predictions based on current state
    static func generatePredictions(entries: [DiaryEntry]) -> [FridayPrediction] {
        let assistant = FridayAssistantEngine.shared
        var candidates: [FridayPrediction] = []

        // Time-based mood prediction
        if let p = timeMoodPrediction(assistant: assistant) { candidates.append(p) }

        // Day-of-week prediction
        if let p = dayOfWeekPrediction(assistant: assistant) { candidates.append(p) }

        // Missing person observation
        if let p = missingPersonPrediction(entries: entries, assistant: assistant) { candidates.append(p) }

        // Topic shift detection
        if let p = topicShiftPrediction(entries: entries, assistant: assistant) { candidates.append(p) }

        // Emotional trajectory warning
        if let p = emotionalTrajectoryPrediction(assistant: assistant) { candidates.append(p) }

        // Streak encouragement
        if let p = streakPrediction(assistant: assistant) { candidates.append(p) }

        // Writing volume change
        if let p = writingVolumePrediction(entries: entries, assistant: assistant) { candidates.append(p) }

        // Growth observation
        if let p = growthPrediction(assistant: assistant) { candidates.append(p) }

        // Mood trigger alert
        if let p = moodTriggerPrediction(entries: entries, assistant: assistant) { candidates.append(p) }

        // Rumination detection
        if let p = ruminationPrediction(entries: entries, assistant: assistant) { candidates.append(p) }

        // Pick up to 3, prefer variety
        var selected: [FridayPrediction] = []
        var usedCategories: Set<FridayPrediction.Category> = []
        for candidate in candidates {
            if !usedCategories.contains(candidate.category) {
                selected.append(candidate)
                usedCategories.insert(candidate.category)
            }
            if selected.count >= 3 { break }
        }
        if selected.count < 3 {
            for candidate in candidates where !selected.contains(where: { $0.message == candidate.message }) {
                selected.append(candidate)
                if selected.count >= 3 { break }
            }
        }

        return selected
    }

    // MARK: - Prediction Generators

    /// "Based on your patterns, evenings are when your mood drops."
    private static func timeMoodPrediction(assistant: FridayAssistantEngine) -> FridayPrediction? {
        let morning = assistant.emotionalSignature.morningMood
        let evening = assistant.emotionalSignature.eveningMood
        guard assistant.emotionalSignature.analysisCount >= 10 else { return nil }

        let diff = morning - evening
        if abs(diff) < 0.15 { return nil }

        if diff > 0 {
            return FridayPrediction(
                message: "Your mornings are brighter than your evenings.",
                detail: "Entries before noon average \(sentimentWord(morning)). After 6pm? \(sentimentWord(evening)). Something shifts during the day.",
                icon: "sunset.fill",
                tint: OffRecordColor.brandPeach,
                category: .mood
            )
        } else {
            return FridayPrediction(
                message: "You come alive in the evenings.",
                detail: "Your evening entries are more positive than mornings. You're not a morning person — and your journal proves it.",
                icon: "moon.stars.fill",
                tint: OffRecordColor.brandLavenderDark,
                category: .mood
            )
        }
    }

    /// "Sundays tend to be your hardest day."
    private static func dayOfWeekPrediction(assistant: FridayAssistantEngine) -> FridayPrediction? {
        let weekday = assistant.emotionalSignature.weekdayMood
        let weekend = assistant.emotionalSignature.weekendMood
        guard assistant.emotionalSignature.analysisCount >= 10 else { return nil }

        let diff = weekday - weekend
        if abs(diff) < 0.15 { return nil }

        let calendar = Calendar.current
        let today = calendar.component(.weekday, from: Date())
        let isWeekend = today == 1 || today == 7

        if diff > 0 && isWeekend {
            return FridayPrediction(
                message: "Weekends are tougher for you.",
                detail: "Your mood tends to dip on weekends. Structure might help — even a short journal entry.",
                icon: "calendar.badge.exclamationmark",
                tint: OffRecordColor.brandPeach,
                category: .mood
            )
        } else if diff < 0 && !isWeekend {
            return FridayPrediction(
                message: "Weekdays weigh on you more.",
                detail: "Your entries are more positive on weekends. Hang in there — the weekend's coming.",
                icon: "briefcase.fill",
                tint: OffRecordColor.brandSky,
                category: .mood
            )
        }

        return nil
    }

    /// "You haven't mentioned Sarah in 2 weeks. You used to talk about her often."
    private static func missingPersonPrediction(entries: [DiaryEntry], assistant: FridayAssistantEngine) -> FridayPrediction? {
        let calendar = Calendar.current
        let recentTexts = entries
            .filter { entry in
                guard let date = entry.date else { return false }
                return (calendar.dateComponents([.day], from: date, to: Date()).day ?? 0) <= 14
            }
            .compactMap { $0.text }
            .joined(separator: " ")
            .lowercased()

        // Find important people (mentioned 5+ times total) not mentioned recently
        let topPeople = assistant.knowledgeGraph.topNodes(ofType: .person, limit: 5)
        for person in topPeople where person.mentions >= 5 {
            if !recentTexts.contains(person.label.lowercased()) {
                let daysSinceLastSeen = calendar.dateComponents([.day], from: person.lastSeen, to: Date()).day ?? 0
                if daysSinceLastSeen >= 10 {
                    return FridayPrediction(
                        message: "You haven't mentioned \(person.label) in \(daysSinceLastSeen) days.",
                        detail: "They used to come up often (\(person.mentions) times total). Missing them?",
                        icon: "person.fill.questionmark",
                        tint: OffRecordColor.brandPeach,
                        category: .people
                    )
                }
            }
        }

        return nil
    }

    /// "Your entries shifted from 'work' to 'health' this week."
    private static func topicShiftPrediction(entries: [DiaryEntry], assistant: FridayAssistantEngine) -> FridayPrediction? {
        let calendar = Calendar.current
        let thisWeek = entries.filter { entry in
            guard let date = entry.date else { return false }
            return (calendar.dateComponents([.day], from: date, to: Date()).day ?? 0) <= 7
        }
        let lastWeek = entries.filter { entry in
            guard let date = entry.date else { return false }
            let days = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
            return days > 7 && days <= 14
        }

        guard thisWeek.count >= 3, lastWeek.count >= 3 else { return nil }

        let thisWeekTopics = extractTopics(from: thisWeek)
        let lastWeekTopics = extractTopics(from: lastWeek)

        guard let thisTop = thisWeekTopics.max(by: { $0.value < $1.value }),
              let lastTop = lastWeekTopics.max(by: { $0.value < $1.value }),
              thisTop.key != lastTop.key,
              thisTop.value >= 3 else { return nil }

        return FridayPrediction(
            message: "Your focus shifted this week.",
            detail: "Last week: \"\(lastTop.key)\". This week: \"\(thisTop.key)\". Intentional or accidental?",
            icon: "arrow.triangle.swap",
            tint: OffRecordColor.brandLavender,
            category: .pattern
        )
    }

    /// "Your mood has been declining for 5 days straight."
    private static func emotionalTrajectoryPrediction(assistant: FridayAssistantEngine) -> FridayPrediction? {
        let sentiments = assistant.emotionalSignature.recentSentiments
        guard sentiments.count >= 5 else { return nil }

        let last5 = Array(sentiments.suffix(5))

        // Check for consistent decline
        var declining = true
        var improving = true
        for i in 1..<last5.count {
            if last5[i] >= last5[i-1] { declining = false }
            if last5[i] <= last5[i-1] { improving = false }
        }

        if declining {
            return FridayPrediction(
                message: "Your mood has been dipping for \(last5.count) entries straight.",
                detail: "Small dips happen. But if this doesn't feel right, talk to someone you trust.",
                icon: "arrow.down.right",
                tint: OffRecordColor.brandCoral,
                category: .mood
            )
        }

        if improving {
            return FridayPrediction(
                message: "Your mood has been climbing for \(last5.count) entries.",
                detail: "Something's going right. Your journal captured the shift.",
                icon: "arrow.up.right",
                tint: OffRecordColor.brandSage,
                category: .growth
            )
        }

        return nil
    }

    /// "You've journaled 5 days in a row. Your longest streak was 12."
    private static func streakPrediction(assistant: FridayAssistantEngine) -> FridayPrediction? {
        let current = assistant.behavioralPatterns.currentStreak
        let longest = assistant.behavioralPatterns.longestStreak
        guard current >= 3 else { return nil }

        if current == longest && current >= 5 {
            return FridayPrediction(
                message: "This is your longest streak ever. \(current) days.",
                detail: "You've never been this consistent. Don't stop now.",
                icon: "flame.fill",
                tint: OffRecordColor.brandPeach,
                category: .nudge
            )
        }

        if current >= 3 && longest > current {
            let remaining = longest - current
            return FridayPrediction(
                message: "\(current) days in a row. Your record is \(longest).",
                detail: "\(remaining) more days to beat it.",
                icon: "flame.fill",
                tint: OffRecordColor.brandPeach,
                category: .nudge
            )
        }

        return nil
    }

    /// "You wrote 3x more this week than last."
    private static func writingVolumePrediction(entries: [DiaryEntry], assistant: FridayAssistantEngine) -> FridayPrediction? {
        let calendar = Calendar.current
        let thisWeek = entries.filter { entry in
            guard let date = entry.date else { return false }
            return (calendar.dateComponents([.day], from: date, to: Date()).day ?? 0) <= 7
        }
        let lastWeek = entries.filter { entry in
            guard let date = entry.date else { return false }
            let days = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
            return days > 7 && days <= 14
        }

        let thisWords = thisWeek.reduce(0) { $0 + ($1.text ?? "").split { $0.isWhitespace }.count }
        let lastWords = lastWeek.reduce(0) { $0 + ($1.text ?? "").split { $0.isWhitespace }.count }

        guard lastWords > 0 else { return nil }
        let ratio = Double(thisWords) / Double(lastWords)

        if ratio > 2.0 {
            return FridayPrediction(
                message: "You wrote \(Int(ratio))x more this week than last.",
                detail: "When you have a lot to say, it usually means something's brewing.",
                icon: "text.alignleft",
                tint: OffRecordColor.brandAqua,
                category: .pattern
            )
        } else if ratio < 0.4 && lastWords > 100 {
            return FridayPrediction(
                message: "You've gone quiet this week.",
                detail: "Last week: \(lastWords) words. This week: \(thisWords). Even one sentence counts.",
                icon: "text.alignleft",
                tint: OffRecordColor.brandSky,
                category: .nudge
            )
        }

        return nil
    }

    /// "3 months ago you were past-focused. Now you write about the future."
    private static func growthPrediction(assistant: FridayAssistantEngine) -> FridayPrediction? {
        guard assistant.thoughtPatterns.analysisCount >= 20 else { return nil }

        let future = assistant.thoughtPatterns.futureOriented
        let growth = assistant.thoughtPatterns.growthMindsetScore
        let awareness = assistant.thoughtPatterns.selfAwarenessLevel

        if growth > 0.7 && awareness > 0.6 {
            return FridayPrediction(
                message: "You're in a growth phase.",
                detail: "Your entries show high self-awareness and a growth mindset. You're actively evolving.",
                icon: "chart.line.uptrend.xyaxis",
                tint: OffRecordColor.brandSage,
                category: .growth
            )
        }

        if future > 0.7 {
            return FridayPrediction(
                message: "You've been focused on what's ahead.",
                detail: "\(Int(future * 100))% of your thinking is future-oriented. Planning mode activated.",
                icon: "scope",
                tint: OffRecordColor.brandAqua,
                category: .growth
            )
        }

        return nil
    }

    /// "Your mood drops every time you mention 'deadlines'."
    private static func moodTriggerPrediction(entries: [DiaryEntry], assistant: FridayAssistantEngine) -> FridayPrediction? {
        let negTriggers = assistant.emotionalSignature.negativeTriggersTopics
            .sorted { $0.value > $1.value }

        guard let topNeg = negTriggers.first, topNeg.value >= 1.0 else { return nil }

        // Check if the trigger appeared in recent entries
        let recentTexts = entries.prefix(5).compactMap { $0.text }.joined(separator: " ").lowercased()
        if recentTexts.contains(topNeg.key.lowercased()) {
            return FridayPrediction(
                message: "Your mood dips when \"\(topNeg.key)\" comes up.",
                detail: "It appeared in your recent entries again. Friday noticed the pattern.",
                icon: "exclamationmark.triangle",
                tint: OffRecordColor.brandCoral,
                category: .mood
            )
        }

        return nil
    }

    /// "You've been writing about the same thing for 2 weeks straight."
    private static func ruminationPrediction(entries: [DiaryEntry], assistant: FridayAssistantEngine) -> FridayPrediction? {
        guard assistant.thoughtPatterns.ruminationTendency > 0.5 else { return nil }

        let persistent = assistant.thoughtPatterns.topicPersistence
            .sorted { $0.value > $1.value }

        guard let topPersistent = persistent.first, topPersistent.value >= 10 else { return nil }

        return FridayPrediction(
            message: "You've been circling around \"\(topPersistent.key)\" a lot.",
            detail: "It's been on your mind for \(topPersistent.value) entries. Processing, or stuck?",
            icon: "arrow.triangle.2.circlepath",
            tint: OffRecordColor.brandLavender,
            category: .pattern
        )
    }

    // MARK: - Helpers

    private static func sentimentWord(_ value: Double) -> String {
        if value > 0.3 { return "positive" }
        if value > 0.1 { return "okay" }
        if value > -0.1 { return "neutral" }
        if value > -0.3 { return "low" }
        return "heavy"
    }

    private static func extractTopics(from entries: [DiaryEntry]) -> [String: Int] {
        var topics: [String: Int] = [:]
        for entry in entries {
            guard let text = entry.text else { continue }
            let words = text.lowercased().split { $0.isWhitespace || $0.isPunctuation }
            for word in words where word.count > 4 && !LocalAIEngine.stopWords.contains(String(word)) {
                topics[String(word), default: 0] += 1
            }
        }
        return topics
    }
}

// MARK: - Predictions View (for FridayView integration)

struct FridayPredictionsSection: View {
    let entries: [DiaryEntry]
    @State private var predictions: [FridayPrediction] = []

    var body: some View {
        Group {
            if !predictions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        FridayMascotView(pose: .thinking, size: 34)
                        Text("Friday noticed...")
                            .font(OffRecordTypography.sectionTitle)
                    }

                    ForEach(predictions) { prediction in
                        predictionCard(prediction)
                    }
                }
            }
        }
        .onAppear { predictions = FridayPredictionEngine.generatePredictions(entries: entries) }
    }

    private func predictionCard(_ prediction: FridayPrediction) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(prediction.tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: prediction.icon)
                    .font(.system(size: 15))
                    .foregroundColor(prediction.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(prediction.message)
                    .font(OffRecordTypography.labelMedium)
                    .foregroundColor(OffRecordColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = prediction.detail {
                    Text(detail)
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRecordContentCard(cornerRadius: OffRecordRadius.md, fill: OffRecordColor.surfaceLavender)
    }
}
