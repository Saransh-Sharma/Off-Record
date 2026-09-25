//
//  ShareableInsightGenerator.swift
//  OffRecord
//
//  Generates shareable weekly insight cards from journal data. Cards should
//  feel personal but reveal nothing private: names of people are hidden from
//  shared images unless the person explicitly opts in.
//
//  All analysis is performed on-device using existing data from
//  FridayAssistantEngine, LocalAIEngine, and raw diary entries.
//

import CoreData
import Foundation
import NaturalLanguage

// MARK: - Shareable Insight Model

struct ShareableInsight: Identifiable {
    let id = UUID()
    let headline: String      // The main line
    let subtext: String        // Supporting detail
    let category: Category
    let dataPoint: String?     // Optional stat to display
    let generatedAt: Date
    /// Plain-language note on how the insight was derived.
    var rationale: String = ""
    /// `DiaryEntry.insightEvidenceKey` values of the entries behind the insight.
    var supportingEntryIDs: [String] = []
    /// Names of real people the insight mentions. Hidden in shared images by default.
    var personNames: [String] = []

    enum Category: String {
        case emotion = "emotion"
        case pattern = "pattern"
        case people = "people"
        case language = "language"
        case growth = "growth"
        case time = "time"

        var icon: String {
            switch self {
            case .emotion: return "heart.text.square"
            case .pattern: return "waveform.path.ecg"
            case .people: return "person.2"
            case .language: return "text.quote"
            case .growth: return "arrow.up.right"
            case .time: return "clock"
            }
        }

        var accentColorName: String {
            switch self {
            case .emotion: return "pink"
            case .pattern: return "purple"
            case .people: return "orange"
            case .language: return "cyan"
            case .growth: return "green"
            case .time: return "indigo"
            }
        }
    }
}

// MARK: - Privacy

enum ShareableInsightPrivacy {
    static let placeholder = "someone"

    /// Personal names that NaturalLanguage finds in `texts`.
    static func detectedNames(in texts: [String]) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        var names: [String] = []
        for text in texts where !text.isEmpty {
            tagger.string = text
            let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
            tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
                if tag == .personalName {
                    let name = String(text[range])
                    if name.count > 1, !names.contains(name) { names.append(name) }
                }
                return true
            }
        }
        return names
    }

    /// Whether `word` reads as a person's name when placed in a neutral sentence.
    static func isLikelyPersonName(_ word: String) -> Bool {
        let candidate = word.prefix(1).uppercased() + word.dropFirst()
        return !detectedNames(in: ["Yesterday I talked with \(candidate) about it."]).isEmpty
    }

    /// Replaces each name (whole word, any case) with a neutral placeholder.
    static func redact(_ text: String, names: [String]) -> String {
        var result = text
        for name in names.sorted(by: { $0.count > $1.count }) {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: placeholder)
        }
        if result.hasPrefix(placeholder) {
            result = placeholder.prefix(1).uppercased() + result.dropFirst()
        }
        return result
    }
}

extension ShareableInsight {
    /// Every name that should be hidden before sharing: tagged people plus any
    /// names NaturalLanguage spots in the visible copy.
    var namesToProtect: [String] {
        var names = personNames
        for name in ShareableInsightPrivacy.detectedNames(in: [headline, subtext, dataPoint ?? ""]) where !names.contains(name) {
            names.append(name)
        }
        return names
    }

    /// The copy to put in a shared image.
    func sharingVersion(includeNames: Bool) -> ShareableInsight {
        let names = namesToProtect
        guard !includeNames, !names.isEmpty else { return self }
        return ShareableInsight(
            headline: ShareableInsightPrivacy.redact(headline, names: names),
            subtext: ShareableInsightPrivacy.redact(subtext, names: names),
            category: category,
            dataPoint: dataPoint.map { ShareableInsightPrivacy.redact($0, names: names) },
            generatedAt: generatedAt,
            rationale: rationale,
            supportingEntryIDs: supportingEntryIDs,
            personNames: []
        )
    }
}

// MARK: - Generator

@MainActor
struct ShareableInsightGenerator {

    private static let maximumEvidenceCount = 12

    // MARK: - Main Entry Point

    /// Generates up to 3 shareable insights from the past 7 days of entries
    static func generateWeeklyInsights(from entries: [DiaryEntry]) -> [ShareableInsight] {
        let calendar = Calendar.current
        let weekEntries = entries.filter { entry in
            guard let date = entry.date else { return false }
            let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
            return daysAgo <= 7
        }

        guard weekEntries.count >= 3 else { return [] }

        let profile = LocalAIEngine.shared.userProfile

        var insights: [ShareableInsight] = []

        // Try each generator, collect all, then pick the best 3
        var candidates: [ShareableInsight] = []

        if let insight = topEmotionInsight(weekEntries: weekEntries) {
            candidates.append(insight)
        }
        if let insight = personSentimentInsight(weekEntries: weekEntries) {
            candidates.append(insight)
        }
        if let insight = shouldVsWantInsight(weekEntries: weekEntries) {
            candidates.append(insight)
        }
        if let insight = dayOfWeekMoodInsight(weekEntries: weekEntries) {
            candidates.append(insight)
        }
        if let insight = topicAvoidanceInsight(weekEntries: weekEntries, profile: profile) {
            candidates.append(insight)
        }
        if let insight = entryLengthEmotionInsight(weekEntries: weekEntries) {
            candidates.append(insight)
        }
        if let insight = selfFocusInsight(weekEntries: weekEntries) {
            candidates.append(insight)
        }
        if let insight = moodTrajectoryInsight(weekEntries: weekEntries) {
            candidates.append(insight)
        }
        if let insight = timeOfDayMoodInsight(weekEntries: weekEntries) {
            candidates.append(insight)
        }
        if let insight = vocabularyInsight(weekEntries: weekEntries) {
            candidates.append(insight)
        }
        if let insight = questionVsStatementInsight(weekEntries: weekEntries) {
            candidates.append(insight)
        }
        if let insight = topConcernInsight(weekEntries: weekEntries) {
            candidates.append(insight)
        }

        // Pick up to 3, preferring different categories
        var usedCategories: Set<ShareableInsight.Category> = []
        for candidate in candidates.shuffled() {
            if !usedCategories.contains(candidate.category) {
                insights.append(candidate)
                usedCategories.insert(candidate.category)
            }
            if insights.count >= 3 { break }
        }

        // If we still have room, add from any category
        if insights.count < 3 {
            for candidate in candidates.shuffled() {
                if !insights.contains(where: { $0.headline == candidate.headline }) {
                    insights.append(candidate)
                }
                if insights.count >= 3 { break }
            }
        }

        return insights
    }

    // MARK: - Helpers

    private static func mood(of entry: DiaryEntry) -> Mood? {
        guard let moodString = entry.value(forKey: "mood") as? String,
              let mood = Mood(rawValue: moodString),
              mood != .none else { return nil }
        return mood
    }

    private static func evidence(_ entries: [DiaryEntry]) -> [String] {
        var seen = Set<String>()
        var keys: [String] = []
        let sorted = entries.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        for entry in sorted where seen.insert(entry.insightEvidenceKey).inserted {
            keys.append(entry.insightEvidenceKey)
            if keys.count == maximumEvidenceCount { break }
        }
        return keys
    }

    private static func sentiment(of text: String) -> Double? {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        return tag.flatMap { Double($0.rawValue) }
    }

    // MARK: - Insight Generators

    /// "Your dominant mood this week: Calm."
    private static func topEmotionInsight(weekEntries: [DiaryEntry]) -> ShareableInsight? {
        let tagged = weekEntries.compactMap { entry in mood(of: entry).map { (entry, $0) } }
        guard tagged.count >= 3 else { return nil }

        let moodCounts = Dictionary(grouping: tagged.map(\.1), by: { $0 }).mapValues { $0.count }
        guard let topMood = moodCounts.max(by: { $0.value < $1.value }) else { return nil }

        let percentage = Int(Double(topMood.value) / Double(tagged.count) * 100)

        return ShareableInsight(
            headline: "Your most common mood this week:\n\(topMood.key.displayName).",
            subtext: "\(percentage)% of your check-ins. The rest were a mix.",
            category: .emotion,
            dataPoint: "\(topMood.key.displayName) \(percentage)%",
            generatedAt: Date(),
            rationale: "Counted from \(tagged.count) mood check-ins in the last 7 days.",
            supportingEntryIDs: evidence(tagged.filter { $0.1 == topMood.key }.map(\.0))
        )
    }

    /// "You mentioned Sarah 8 times this week."
    private static func personSentimentInsight(weekEntries: [DiaryEntry]) -> ShareableInsight? {
        let tagger = NLTagger(tagSchemes: [.nameType])
        var personSentiments: [String: (count: Int, totalSentiment: Double, entries: [DiaryEntry])] = [:]

        for entry in weekEntries {
            guard let text = entry.text, !text.isEmpty else { continue }
            tagger.string = text
            let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
            let entrySentiment = sentiment(of: text) ?? 0

            tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
                if tag == .personalName {
                    let name = String(text[range])
                    if name.count > 1 {
                        var existing = personSentiments[name] ?? (count: 0, totalSentiment: 0, entries: [])
                        existing.count += 1
                        existing.totalSentiment += entrySentiment
                        if !existing.entries.contains(where: { $0.objectID == entry.objectID }) {
                            existing.entries.append(entry)
                        }
                        personSentiments[name] = existing
                    }
                }
                return true
            }
        }

        // Find someone mentioned 3+ times with notable sentiment
        guard let topPerson = personSentiments
            .filter({ $0.value.count >= 3 })
            .max(by: { abs($0.value.totalSentiment / Double($0.value.count)) < abs($1.value.totalSentiment / Double($1.value.count)) })
        else { return nil }

        let avgSentiment = topPerson.value.totalSentiment / Double(topPerson.value.count)
        let toneLine: String
        if avgSentiment < -0.1 {
            toneLine = "Those entries tend to read a little heavier."
        } else if avgSentiment > 0.1 {
            toneLine = "Those entries tend to read a little lighter."
        } else {
            toneLine = "Those entries read about the same as the rest."
        }

        return ShareableInsight(
            headline: "You mentioned \(topPerson.key) \(topPerson.value.count) times this week.",
            subtext: toneLine,
            category: .people,
            dataPoint: "\(topPerson.value.count)x",
            generatedAt: Date(),
            rationale: "Names are recognized on-device. Tone is estimated from the entries that mention them.",
            supportingEntryIDs: evidence(topPerson.value.entries),
            personNames: [topPerson.key]
        )
    }

    /// "You said 'should' 12 times. 'Want' only twice."
    private static func shouldVsWantInsight(weekEntries: [DiaryEntry]) -> ShareableInsight? {
        let obligationWords = ["should", "must", "have to", "need to", "ought to"]
        let desireWords = ["want", "wish", "hope", "dream", "love to", "excited to"]

        var obligationCount = 0
        var desireCount = 0
        var matchingEntries: [DiaryEntry] = []

        for entry in weekEntries {
            let text = (entry.text ?? "").lowercased()
            let obligations = obligationWords.reduce(0) { $0 + text.components(separatedBy: $1).count - 1 }
            let desires = desireWords.reduce(0) { $0 + text.components(separatedBy: $1).count - 1 }
            obligationCount += obligations
            desireCount += desires
            if obligations + desires > 0 { matchingEntries.append(entry) }
        }

        guard obligationCount >= 3 || desireCount >= 3 else { return nil }
        let rationale = "Counts words like \u{201C}should\u{201D} and \u{201C}have to\u{201D} against \u{201C}want\u{201D} and \u{201C}hope\u{201D} in this week's entries."

        if obligationCount > desireCount * 2 && obligationCount >= 5 {
            return ShareableInsight(
                headline: "You said \"should\" \(obligationCount) times this week.\n\"Want\"? \(desireCount).",
                subtext: "Lots of obligations on the page. Just something to notice.",
                category: .language,
                dataPoint: "should: \(obligationCount) vs want: \(desireCount)",
                generatedAt: Date(),
                rationale: rationale,
                supportingEntryIDs: evidence(matchingEntries)
            )
        } else if desireCount > obligationCount * 2 && desireCount >= 5 {
            return ShareableInsight(
                headline: "You said \"want\" \(desireCount) times this week.\n\"Should\"? \(obligationCount).",
                subtext: "Plenty of wants and hopes on the page this week.",
                category: .language,
                dataPoint: "want: \(desireCount) vs should: \(obligationCount)",
                generatedAt: Date(),
                rationale: rationale,
                supportingEntryIDs: evidence(matchingEntries)
            )
        }

        return nil
    }

    /// "Most anxious on Sundays. Most calm on Wednesdays."
    private static func dayOfWeekMoodInsight(weekEntries: [DiaryEntry]) -> ShareableInsight? {
        let calendar = Calendar.current
        var dayMoods: [Int: [(entry: DiaryEntry, mood: Mood)]] = [:]

        for entry in weekEntries {
            guard let date = entry.date, let mood = mood(of: entry) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            dayMoods[weekday, default: []].append((entry, mood))
        }

        guard dayMoods.count >= 3 else { return nil }

        let dayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let negativeMoods: Set<Mood> = [.anxious, .sad, .angry, .tired]
        let positiveMoods: Set<Mood> = [.happy, .excited, .grateful, .calm]

        // Find most positive and most negative days
        var bestDay: (day: Int, ratio: Double) = (1, 0)
        var worstDay: (day: Int, ratio: Double) = (1, 1)

        for (day, items) in dayMoods where !items.isEmpty {
            let positiveRatio = Double(items.filter { positiveMoods.contains($0.mood) }.count) / Double(items.count)
            if positiveRatio > bestDay.ratio { bestDay = (day, positiveRatio) }
            if positiveRatio < worstDay.ratio { worstDay = (day, positiveRatio) }
        }

        guard bestDay.day != worstDay.day else { return nil }

        let worstMood = dayMoods[worstDay.day]?
            .map(\.mood)
            .filter { negativeMoods.contains($0) }
            .reduce(into: [:]) { counts, mood in counts[mood, default: 0] += 1 }
            .max(by: { $0.value < $1.value })?.key

        let bestMood = dayMoods[bestDay.day]?
            .map(\.mood)
            .filter { positiveMoods.contains($0) }
            .reduce(into: [:]) { counts, mood in counts[mood, default: 0] += 1 }
            .max(by: { $0.value < $1.value })?.key

        let worstLabel = worstMood?.displayName.lowercased() ?? "low"
        let bestLabel = bestMood?.displayName.lowercased() ?? "good"
        let supporting = (dayMoods[worstDay.day] ?? []) + (dayMoods[bestDay.day] ?? [])

        return ShareableInsight(
            headline: "Most \(worstLabel) on \(dayNames[worstDay.day]).\nMost \(bestLabel) on \(dayNames[bestDay.day]).",
            subtext: "Your week had a shape to it.",
            category: .time,
            dataPoint: nil,
            generatedAt: Date(),
            rationale: "Compares the moods you tagged on each day of the last week.",
            supportingEntryIDs: evidence(supporting.map(\.entry))
        )
    }

    /// "You haven't mentioned [topic] this week."
    private static func topicAvoidanceInsight(weekEntries: [DiaryEntry], profile: UserProfile) -> ShareableInsight? {
        let weekText = weekEntries.compactMap { $0.text }.joined(separator: " ").lowercased()

        // Find top historical topics that are absent this week
        let topHistorical = profile.commonTopics
            .sorted { $0.value > $1.value }
            .prefix(5)

        for (topic, count) in topHistorical where count >= 5 {
            let lowered = topic.lowercased()
            if !weekText.contains(lowered) {
                return ShareableInsight(
                    headline: "\"\(topic)\" didn't come up this week.",
                    subtext: "It used to appear often. Just noticing.",
                    category: .pattern,
                    dataPoint: "\(count) mentions before",
                    generatedAt: Date(),
                    rationale: "Compares this week's entries with topics from earlier entries.",
                    personNames: ShareableInsightPrivacy.isLikelyPersonName(topic) ? [topic] : []
                )
            }
        }

        return nil
    }

    /// "You write 3x more when you're anxious."
    private static func entryLengthEmotionInsight(weekEntries: [DiaryEntry]) -> ShareableInsight? {
        var moodWordCounts: [Mood: [Int]] = [:]
        var moodEntries: [Mood: [DiaryEntry]] = [:]

        for entry in weekEntries {
            guard let text = entry.text, let mood = mood(of: entry) else { continue }
            let wordCount = text.split { $0.isWhitespace }.count
            moodWordCounts[mood, default: []].append(wordCount)
            moodEntries[mood, default: []].append(entry)
        }

        guard moodWordCounts.count >= 2 else { return nil }

        let averages = moodWordCounts.mapValues { counts -> Double in
            Double(counts.reduce(0, +)) / Double(counts.count)
        }

        guard let longest = averages.max(by: { $0.value < $1.value }),
              let shortest = averages.min(by: { $0.value < $1.value }),
              longest.key != shortest.key,
              shortest.value > 0 else { return nil }

        let ratio = longest.value / shortest.value
        guard ratio >= 1.5 else { return nil }

        let ratioText = ratio >= 2.5 ? "\(Int(ratio))x" : String(format: "%.1fx", ratio)

        return ShareableInsight(
            headline: "You write \(ratioText) more when you're \(longest.key.displayName.lowercased()).",
            subtext: "Entries tagged \(shortest.key.displayName.lowercased()) tend to be shorter.",
            category: .pattern,
            dataPoint: "\(Int(longest.value)) vs \(Int(shortest.value)) words",
            generatedAt: Date(),
            rationale: "Average word count of this week's entries, grouped by mood.",
            supportingEntryIDs: evidence((moodEntries[longest.key] ?? []) + (moodEntries[shortest.key] ?? []))
        )
    }

    /// "82% of your sentences start with 'I'."
    private static func selfFocusInsight(weekEntries: [DiaryEntry]) -> ShareableInsight? {
        let allText = weekEntries.compactMap { $0.text }.joined(separator: " ")
        let sentences = allText.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard sentences.count >= 10 else { return nil }

        let iSentences = sentences.filter { sentence in
            let first = sentence.split(separator: " ").first?.lowercased()
            return first == "i" || first == "i'm" || first == "i've" || first == "i'll" || first == "i'd"
        }

        let ratio = Double(iSentences.count) / Double(sentences.count)
        let percentage = Int(ratio * 100)

        if percentage >= 60 {
            return ShareableInsight(
                headline: "\(percentage)% of your sentences start with \"I\".",
                subtext: "Your journal centers on you, which is exactly what it's for.",
                category: .language,
                dataPoint: "\(percentage)%",
                generatedAt: Date(),
                rationale: "Based on \(sentences.count) sentences written this week.",
                supportingEntryIDs: evidence(weekEntries.filter { !($0.text ?? "").isEmpty })
            )
        }

        return nil
    }

    /// "Your mood climbed all week."
    private static func moodTrajectoryInsight(weekEntries: [DiaryEntry]) -> ShareableInsight? {
        let sorted = weekEntries
            .filter { $0.date != nil }
            .sorted { ($0.date ?? Date()) < ($1.date ?? Date()) }

        var scored: [(entry: DiaryEntry, score: Double)] = []
        for entry in sorted {
            guard let text = entry.text, !text.isEmpty, let score = sentiment(of: text) else { continue }
            scored.append((entry, score))
        }

        guard scored.count >= 4 else { return nil }

        // Check for consistent trend
        let firstHalf = scored.prefix(scored.count / 2).map(\.score)
        let secondHalf = scored.suffix(scored.count / 2).map(\.score)
        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)
        let diff = secondAvg - firstAvg
        let rationale = "Tone of \(scored.count) entries, estimated on-device, early in the week versus later."

        if diff > 0.2 {
            return ShareableInsight(
                headline: "Your entries brightened as the week went on.",
                subtext: "Whatever you're doing, it seems to be helping.",
                category: .growth,
                dataPoint: nil,
                generatedAt: Date(),
                rationale: rationale,
                supportingEntryIDs: evidence(scored.map(\.entry))
            )
        } else if diff < -0.2 {
            return ShareableInsight(
                headline: "Your entries got a little heavier as the week went on.",
                subtext: "Dips are a normal part of any week. Be gentle with yourself.",
                category: .emotion,
                dataPoint: nil,
                generatedAt: Date(),
                rationale: rationale,
                supportingEntryIDs: evidence(scored.map(\.entry))
            )
        }

        return nil
    }

    /// "Brightest entries around 7am. Heavier ones around 11pm."
    private static func timeOfDayMoodInsight(weekEntries: [DiaryEntry]) -> ShareableInsight? {
        let calendar = Calendar.current
        var hourSentiments: [Int: [(entry: DiaryEntry, score: Double)]] = [:]

        for entry in weekEntries {
            guard let date = entry.date, let text = entry.text, !text.isEmpty, let score = sentiment(of: text) else { continue }
            let hour = calendar.component(.hour, from: date)
            hourSentiments[hour, default: []].append((entry, score))
        }

        guard hourSentiments.count >= 2 else { return nil }

        let averages = hourSentiments.mapValues { items in items.reduce(0) { $0 + $1.score } / Double(items.count) }
        guard let bestHour = averages.max(by: { $0.value < $1.value }),
              let worstHour = averages.min(by: { $0.value < $1.value }),
              bestHour.key != worstHour.key,
              bestHour.value - worstHour.value > 0.2 else { return nil }

        let formatHour = { (h: Int) -> String in
            if h == 0 { return "midnight" }
            if h == 12 { return "noon" }
            return h < 12 ? "\(h)am" : "\(h - 12)pm"
        }
        let supporting = (hourSentiments[bestHour.key] ?? []) + (hourSentiments[worstHour.key] ?? [])

        return ShareableInsight(
            headline: "Brightest entries around \(formatHour(bestHour.key)).\nHeavier ones around \(formatHour(worstHour.key)).",
            subtext: "Time of day seems to color how you write.",
            category: .time,
            dataPoint: nil,
            generatedAt: Date(),
            rationale: "Tone of this week's entries, estimated on-device and grouped by hour.",
            supportingEntryIDs: evidence(supporting.map(\.entry))
        )
    }

    /// "347 unique words this week."
    private static func vocabularyInsight(weekEntries: [DiaryEntry]) -> ShareableInsight? {
        let allText = weekEntries.compactMap { $0.text }.joined(separator: " ")
        let words = allText.lowercased().split { $0.isWhitespace || $0.isPunctuation }
        let uniqueWords = Set(words)

        guard words.count >= 50 else { return nil }

        let richness = Double(uniqueWords.count) / Double(words.count)
        let percentage = Int(richness * 100)

        if uniqueWords.count > 200 {
            return ShareableInsight(
                headline: "\(uniqueWords.count) unique words this week.",
                subtext: "Vocabulary richness: \(percentage)%. You had a lot to say.",
                category: .language,
                dataPoint: "\(uniqueWords.count) words",
                generatedAt: Date(),
                rationale: "Counts distinct words across \(weekEntries.count) entries from the last 7 days.",
                supportingEntryIDs: evidence(weekEntries.filter { !($0.text ?? "").isEmpty })
            )
        }

        return nil
    }

    /// "You asked 14 questions this week."
    private static func questionVsStatementInsight(weekEntries: [DiaryEntry]) -> ShareableInsight? {
        let questionEntries = weekEntries.filter { ($0.text ?? "").contains("?") }
        let questionCount = questionEntries.reduce(0) { $0 + ($1.text ?? "").components(separatedBy: "?").count - 1 }

        guard questionCount >= 5 else { return nil }

        return ShareableInsight(
            headline: "You asked \(questionCount) questions this week.",
            subtext: "Asking is a good sign you're thinking things through.",
            category: .pattern,
            dataPoint: "\(questionCount) questions",
            generatedAt: Date(),
            rationale: "Counts question marks in this week's entries.",
            supportingEntryIDs: evidence(questionEntries)
        )
    }

    /// "Your #1 topic this week: work."
    private static func topConcernInsight(weekEntries: [DiaryEntry]) -> ShareableInsight? {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        var topicEntries: [String: [DiaryEntry]] = [:]

        for entry in weekEntries {
            guard let text = entry.text, !text.isEmpty else { continue }
            tagger.string = text
            var entryTopics: Set<String> = []

            let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]
            tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
                if tag == .noun {
                    let word = String(text[range]).lowercased()
                    if word.count > 3 && !LocalAIEngine.shared.isStopWord(word) {
                        entryTopics.insert(word)
                    }
                }
                return true
            }

            for topic in entryTopics {
                topicEntries[topic, default: []].append(entry)
            }
        }

        // Find a topic that appears in most entries
        let threshold = max(3, weekEntries.count / 2)
        guard let topTopic = topicEntries.filter({ $0.value.count >= threshold }).max(by: { $0.value.count < $1.value.count }) else {
            return nil
        }

        let count = topTopic.value.count
        let ratio = Double(count) / Double(weekEntries.count)
        let ratioText = ratio >= 0.9 ? "almost every entry" : "\(count) of \(weekEntries.count) entries"
        let topic = topTopic.key.capitalized

        return ShareableInsight(
            headline: "Your #1 topic this week:\n\"\(topic)\"",
            subtext: "It showed up in \(ratioText).",
            category: .pattern,
            dataPoint: "\(count)/\(weekEntries.count) entries",
            generatedAt: Date(),
            rationale: "The noun that appeared in the most entries this week.",
            supportingEntryIDs: evidence(topTopic.value),
            personNames: ShareableInsightPrivacy.isLikelyPersonName(topic) ? [topic] : []
        )
    }
}

// MARK: - LocalAIEngine Extension

extension LocalAIEngine {
    func isStopWord(_ word: String) -> Bool {
        Self.stopWords.contains(word)
    }
}
