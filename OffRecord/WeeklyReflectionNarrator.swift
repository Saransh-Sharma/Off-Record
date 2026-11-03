//
//  WeeklyReflectionNarrator.swift
//  OffRecord
//
//  Lets the on-device model rephrase two lines of a Weekly Reflection: the
//  cover line (`heroSentence`) and the `summary`. Everything else, and every
//  fact the model sees, stays deterministic: theme names and counts, entry
//  and word counts, the mood arc, and the wins and frictions text. The model
//  never sees entry text, so it can't quote or analyze a heavy entry, and a
//  week with any distress (`safetyLevel != .none`) skips the model entirely.
//  Output passes the same checks as the rest of Friday's generated text plus
//  the report's own validation; on any failure the deterministic lines stay.
//

import Foundation
import JournalFoundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Facts

/// The only input the model gets: numbers and phrases the app already computed.
struct WeeklyReflectionNarrationFacts: Equatable, Sendable {
    struct Theme: Equatable, Sendable {
        let name: String
        let entryCount: Int
    }

    let isLightWeek: Bool
    let entryCount: Int
    let entryDays: Int
    let wordCount: Int
    let themes: [Theme]
    /// "Got Lighter", "Got Heavier", or "Steady", plus its sentence.
    let moodArc: String?
    let moodArcDescription: String?
    let wins: [String]
    let frictions: [String]
    let deterministicHero: String
    let deterministicSummary: String

    /// Nil when the week may not be narrated: not ready, empty, or any distress.
    init?(report: WeeklyReflectionReport, entries: [WeeklyReflectionEntrySnapshot]) {
        guard report.safetyLevel == .none,
              report.status == .ready || report.status == .seen,
              report.eligibility != .empty else { return nil }
        let included = Set(report.includedEntryIds)
        let weekEntries = entries.filter { included.contains($0.id) }
        // The report's filter missed nothing, but check again: a heavy entry means no model.
        guard !weekEntries.isEmpty,
              JournalRiskClassifier.level(forAll: weekEntries.map(\.text)) == .none else { return nil }

        isLightWeek = report.eligibility == .light
        entryCount = weekEntries.count
        entryDays = Set(weekEntries.map { Calendar.current.startOfDay(for: $0.date) }).count
        wordCount = weekEntries.reduce(0) { $0 + $1.wordCount }
        themes = report.themes.map { Theme(name: $0.title, entryCount: $0.evidenceRefs.count) }
        moodArc = report.emotionalArc?.label
        moodArcDescription = report.emotionalArc?.description
        wins = report.wins
        frictions = report.frictions
        deterministicHero = report.heroSentence
        deterministicSummary = report.summary
    }

    init(
        isLightWeek: Bool,
        entryCount: Int,
        entryDays: Int,
        wordCount: Int,
        themes: [Theme],
        moodArc: String?,
        moodArcDescription: String?,
        wins: [String],
        frictions: [String],
        deterministicHero: String,
        deterministicSummary: String
    ) {
        self.isLightWeek = isLightWeek
        self.entryCount = entryCount
        self.entryDays = entryDays
        self.wordCount = wordCount
        self.themes = themes
        self.moodArc = moodArc
        self.moodArcDescription = moodArcDescription
        self.wins = wins
        self.frictions = frictions
        self.deterministicHero = deterministicHero
        self.deterministicSummary = deterministicSummary
    }

    /// Every number the prose may state.
    var allowedNumbers: Set<Int> {
        Set([entryCount, entryDays, wordCount] + themes.map(\.entryCount))
    }

    /// The text the prose's names and topics must come from.
    var groundingText: String {
        (themes.map(\.name) + wins + frictions + [moodArcDescription ?? "", deterministicHero, deterministicSummary])
            .joined(separator: ". ")
    }

    var promptBlock: String {
        var lines = [
            "Entries: \(entryCount) on \(entryDays) days, about \(wordCount) words.",
        ]
        if themes.isEmpty {
            lines.append("Themes: none.")
        } else {
            lines.append("Themes: " + themes.map { "\($0.name) (\($0.entryCount) entries)" }.joined(separator: "; ") + ".")
        }
        if let moodArcDescription { lines.append("Mood across the week: \(moodArcDescription)") }
        if !wins.isEmpty { lines.append("Went well: " + wins.joined(separator: " ")) }
        if !frictions.isEmpty { lines.append("Was hard: " + frictions.joined(separator: " ")) }
        return lines.joined(separator: "\n")
    }
}

/// The two lines the model may write.
struct WeeklyReflectionNarration: Equatable, Sendable {
    let heroSentence: String
    let summary: String
}

// MARK: - Seam

protocol WeeklyReflectionNarrating: Sendable {
    /// Returns nil when no model is available. Throws when the model ran and failed.
    func narrate(_ facts: WeeklyReflectionNarrationFacts) async throws -> WeeklyReflectionNarration?
}

// MARK: - Narrator

enum WeeklyReflectionNarrator {
    static let maximumHeroWords = 14
    static let maximumSummaryWords = 50
    static let maximumSummarySentences = 3

    /// `report` with the model's cover line and summary when they pass every
    /// check, otherwise `report` unchanged.
    static func narrated(
        _ report: WeeklyReflectionReport,
        entries: [WeeklyReflectionEntrySnapshot],
        narrator: (any WeeklyReflectionNarrating)? = systemNarrator(),
        isModelAvailable: Bool = FridayLanguageModel.isAvailable
    ) async -> WeeklyReflectionReport {
        guard isModelAvailable, let narrator,
              let facts = WeeklyReflectionNarrationFacts(report: report, entries: entries) else { return report }
        guard let raw = try? await narrator.narrate(facts),
              let narration = validated(raw, facts: facts) else { return report }

        var candidate = report
        candidate.heroSentence = narration.heroSentence
        candidate.summary = narration.summary
        guard WeeklyReflectionGenerationService.validate(candidate),
              WeeklyReflectionSafetyFilter.isValidOutput(candidate) else { return report }
        return candidate
    }

    /// The narration as it will be shown, or nil when either line breaks a rule.
    static func validated(_ raw: WeeklyReflectionNarration, facts: WeeklyReflectionNarrationFacts) -> WeeklyReflectionNarration? {
        let hero = FridayOutputValidator.normalized(raw.heroSentence)
        let summary = FridayOutputValidator.normalized(raw.summary)
        guard (3...maximumHeroWords).contains(FridayOutputValidator.wordCount(hero)),
              sentenceCount(hero) == 1, !hero.contains("?") else { return nil }
        guard (5...maximumSummaryWords).contains(FridayOutputValidator.wordCount(summary)),
              (1...maximumSummarySentences).contains(sentenceCount(summary)), !summary.contains("?") else { return nil }
        for line in [hero, summary] {
            guard isGrounded(line, facts: facts) else { return nil }
        }
        // "At most one I per card" (Voice, Friday’s voice).
        let pronounI = FridayOutputValidator.words(in: hero + " " + summary).filter { ["i", "i'm", "i've", "i'll", "i'd"].contains($0) }
        guard pronounI.count <= 1 else { return nil }
        return WeeklyReflectionNarration(heroSentence: hero, summary: summary)
    }

    private static func isGrounded(_ line: String, facts: WeeklyReflectionNarrationFacts) -> Bool {
        guard line.first?.isUppercase == true, line.last.map({ ".".contains($0) }) == true else { return false }
        guard FridayOutputValidator.isAcceptable(line) else { return false }
        // Every number comes from the facts.
        let numbers = line.split { !$0.isNumber }.compactMap { Int($0) }
        guard numbers.allSatisfy(facts.allowedNumbers.contains) else { return false }
        // Names and topics come from the facts, never from entries the model didn't see.
        guard FridayOutputValidator.inventedNames(in: line, source: facts.groundingText).isEmpty else { return false }
        guard FridayOutputValidator.inventedTopics(in: line, source: facts.groundingText, allowing: weeklyNouns).isEmpty else { return false }
        return true
    }

    /// Nouns a weekly line can use without the facts spelling them out.
    private static let weeklyNouns: Set<String> = [
        "word", "words", "theme", "themes", "writing", "reflection", "half", "pace",
        "mix", "share", "highs", "lows", "high", "low", "tone", "balance",
    ]

    static func sentenceCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { substring, _, _, _ in
            if substring?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { count += 1 }
        }
        return count
    }

    static func systemNarrator() -> (any WeeklyReflectionNarrating)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return FoundationModelsWeeklyReflectionNarrator()
        }
        #endif
        return nil
    }
}

// MARK: - Foundation Models

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedWeeklyReflectionNarration {
    @Guide(description: "The cover line: one sentence of at most 14 words about the week.")
    let heroSentence: String
    @Guide(description: "One to three short sentences, at most 50 words, built only from the facts.")
    let summary: String
}

@available(iOS 26.0, *)
struct FoundationModelsWeeklyReflectionNarrator: WeeklyReflectionNarrating {
    static let instructions = """
    You are Friday, the companion in a private journal app. You write two lines of the person’s Weekly Reflection from facts the app counted.
    Rules:
    - Use only the facts given. Every number and theme you mention must appear in the facts. Never invent events, people, places, feelings, or causes.
    - Speak to the person as you. Lead with facts and numbers. Plain, calm words, short sentences.
    - The cover line is one sentence of at most 14 words. The summary is one to three sentences, at most 50 words in all.
    - No questions, advice, praise, or reassurance. No exclamation marks, emoji, quotation marks, or em dashes.
    - Never use these words: gentle, journey, safe space, valid, brave, self-care, just, simply, actually, unlock, thread, noticed.
    - Never use clinical or diagnostic words, and never describe the person as a condition.
    """

    func narrate(_ facts: WeeklyReflectionNarrationFacts) async throws -> WeeklyReflectionNarration? {
        let model = SystemLanguageModel.default
        guard model.availability == .available else { return nil }
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let response = try await session.respond(
            to: "Facts about this week:\n\(facts.promptBlock)\n\nWrite the cover line and the summary.",
            generating: GeneratedWeeklyReflectionNarration.self,
            options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 160)
        )
        return WeeklyReflectionNarration(heroSentence: response.content.heroSentence, summary: response.content.summary)
    }
}
#endif
