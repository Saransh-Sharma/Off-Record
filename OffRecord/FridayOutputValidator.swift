//
//  FridayOutputValidator.swift
//  OffRecord
//
//  The one gate every piece of model-written text passes before anyone sees
//  it. It enforces the mechanical parts of the Voice standard in "OffRecord
//  Design.md" (banned words, punctuation, "I noticed"), the safety contract
//  (no clinical terms, no Weekly forbidden phrases, nothing that reads as
//  high-risk), and grounding (names and topics must come from the source).
//  Anything that fails is dropped and the caller shows its deterministic
//  text instead. Nothing here repairs wording beyond trimming and quotes.
//

import Foundation
import JournalFoundation
import SemanticMemoryKit

enum FridayOutputValidator {
    /// Banned words and phrases from the Voice standard, lowercased. // copy-lint:ignore
    static let bannedPhrases: [String] = [
        "gentle", "gently", "softly", "space to", "safe space", "journey", "unlock", // copy-lint:ignore
        "effortless", "seamless", "thread", "threads", "carry forward", "let's", "here's", // copy-lint:ignore
        "it looks like", "valid", "brave", "self-care", "self care", "actually", "simply", // copy-lint:ignore
        "just", "worth naming", "worth noticing", "friday noticed", "i noticed", "i've noticed", // copy-lint:ignore
        "please", "oops", "diary", "journal memory", "data point", // copy-lint:ignore
        "voice note", "embedding", "semantic", "baseline", "as an ai", "language model", // copy-lint:ignore
    ]

    /// Characters generated text may never contain (straight quotes mean it quoted or wrapped a sentence).
    static let bannedCharacters: [Character] = ["!", "—", "•", "\""]

    // MARK: Normalizing

    /// Trims, collapses whitespace, curls apostrophes, and unwraps quotes that wrap the whole text.
    static func normalized(_ text: String) -> String {
        var value = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let wrappers: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'"), ("‘", "’")]
        for (open, close) in wrappers where value.count >= 2 && value.first == open && value.last == close {
            value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        value = value.replacingOccurrences(of: "...", with: "…")
        // Curly apostrophes inside words, as the standard asks.
        value = value.replacingOccurrences(of: "'", with: "’")
        return value
    }

    // MARK: Checks

    /// Every reason `text` can't be shown. Empty means it passed.
    /// - Parameter allowedRisk: the heaviest wording the text may carry. Chat answers to a
    ///   heavy question may echo it; questions, titles, and weekly prose may not.
    static func violations(in text: String, allowedRisk: JournalSafetyLevel = .mildDistress) -> [String] {
        var problems: [String] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ["empty"] }

        let comparable = trimmed.lowercased().replacingOccurrences(of: "’", with: "'")
        for phrase in bannedPhrases where containsWord(phrase, in: comparable) {
            problems.append("banned: \(phrase)")
        }
        for character in bannedCharacters where trimmed.contains(character) {
            problems.append("character: \(character)")
        }
        if trimmed.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) {
            problems.append("emoji")
        }
        problems += SensitiveDomainPolicy.clinicalTermViolations(in: trimmed).map { "clinical: \($0)" }
        problems += WeeklyReflectionSafetyFilter.forbiddenTermViolations(in: trimmed).map { "forbidden: \($0)" }
        // Generated text must never itself read as heavy or high-risk.
        if JournalRiskClassifier.level(for: trimmed) > min(allowedRisk, .moderateConcern) {
            problems.append("risk")
        }
        if WeeklyReflectionSafetyFilter.sanitized(trimmed) != trimmed {
            problems.append("sanitizer")
        }
        return problems
    }

    static func isAcceptable(_ text: String, allowedRisk: JournalSafetyLevel = .mildDistress) -> Bool {
        violations(in: text, allowedRisk: allowedRisk).isEmpty
    }

    /// Names in `text` that don't appear in `source`. A capitalized word inside
    /// a sentence counts as a name, and so does anything NaturalLanguage tags
    /// as one. The match is case-sensitive, so Title Case words ("What Made It
    /// Hard") fail unless the source writes them that way. Weekday and month
    /// names and "I" are allowed.
    static func inventedNames(in text: String, source: String) -> [String] {
        let sourceWords = Set(casedWords(in: source))
        var candidates = Set(midSentenceCapitalizedWords(in: text))
        for entity in EntityExtractor.nameOccurrences(in: text) {
            for part in entity.text.split(separator: " ") { candidates.insert(String(part)) }
        }
        return candidates
            .map(stripPossessive)
            .filter { candidate in
                !alwaysAllowedCapitalized.contains(candidate.lowercased()) && !sourceWords.contains(candidate)
            }
            .sorted()
    }

    /// Mid-sentence capitalized words in `text`, for sentence-case checks.
    static func midSentenceCapitalizedWords(in text: String) -> [String] {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var result: [String] = []
        var startsSentence = true
        for token in tokens {
            let word = token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if !startsSentence, let first = word.first, first.isUppercase {
                result.append(stripPossessive(word))
            }
            startsSentence = token.last.map { ".?!:".contains($0) } ?? false
        }
        return result
    }

    /// Nouns in `text` that the source never mentions, allowing a short list of
    /// everyday words. Empty when no part-of-speech model is available.
    static func inventedTopics(in text: String, source: String, allowing extra: Set<String> = []) -> [String] {
        let sourceStems = Set(words(in: source).map(stem))
        return EntityExtractor.nouns(in: text, minimumLength: 3, excluding: EntityExtractor.commonWords)
            .filter { noun in
                !genericNouns.contains(noun) && !extra.contains(noun) && !sourceStems.contains(stem(noun))
            }
    }

    /// Whether `text` shares at least one meaningful word with `source`.
    static func sharesContent(_ text: String, with source: String) -> Bool {
        let sourceStems = Set(contentWords(in: source).map(stem))
        return contentWords(in: text).contains { sourceStems.contains(stem($0)) }
    }

    // MARK: Helpers

    /// Lowercased words, apostrophes kept inside words.
    static func words(in text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" }
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .map { $0.hasSuffix("'s") ? String($0.dropLast(2)) : $0 }
            .filter { !$0.isEmpty }
    }

    /// Words as written, without surrounding punctuation or a possessive.
    static func casedWords(in text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }
            .map { stripPossessive(String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'’"))) }
            .filter { !$0.isEmpty }
    }

    static func stripPossessive(_ word: String) -> String {
        for suffix in ["’s", "'s"] where word.hasSuffix(suffix) {
            return String(word.dropLast(2))
        }
        return word
    }

    static func contentWords(in text: String) -> [String] {
        words(in: text).filter { $0.count >= 4 && !EntityExtractor.commonWords.contains($0) && !TextSignals.stopWords.contains($0) && !questionWords.contains($0) }
    }

    /// A rough stem so "walks", "walked", and "walking" match "walk".
    static func stem(_ word: String) -> String {
        var value = word.lowercased()
        if value.hasSuffix("ies"), value.count > 4 { return String(value.dropLast(3)) + "y" }
        for suffix in ["ing", "ed", "es", "s"] where value.hasSuffix(suffix) && value.count - suffix.count >= 3 {
            if suffix == "s", value.hasSuffix("ss") { continue }
            value = String(value.dropLast(suffix.count))
            break
        }
        return value
    }

    static func containsWord(_ phrase: String, in lowercasedText: String) -> Bool {
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![\\p{L}\\p{N}])"
        return lowercasedText.range(of: pattern, options: .regularExpression) != nil
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static let alwaysAllowedCapitalized: Set<String> = [
        "i", "i'm", "i’m", "i've", "i’ve", "i'd", "i’d", "i'll", "i’ll",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august",
        "september", "october", "november", "december", "apple", "intelligence",
    ]

    private static let questionWords: Set<String> = ["what", "when", "where", "which", "who", "whom", "whose", "why", "how", "does", "would", "could", "should", "might"]

    /// Everyday nouns a question or title can use without the entry naming them.
    static let genericNouns: Set<String> = [
        "day", "days", "time", "times", "week", "today", "tonight", "tomorrow", "yesterday",
        "morning", "evening", "night", "afternoon", "weekend", "part", "parts", "thing", "things",
        "way", "ways", "feeling", "feelings", "mind", "something", "someone", "anything", "anyone",
        "everything", "lot", "kind", "sense", "difference", "step", "steps", "life", "rest",
        "most", "end", "start", "next", "last", "first", "change", "entry", "entries",
        "mood", "moods", "self", "yourself", "you", "people", "person",
    ]
}
