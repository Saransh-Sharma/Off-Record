//
//  JournalRiskClassifier.swift
//  JournalFoundation
//
//  Conservative lexical screen that maps journal text or a question to a
//  `JournalSafetyLevel`. Every AI surface runs it before analyzing, quoting,
//  or asking about content, and `SensitiveDomainPolicy` turns the level into
//  a response mode.
//
//  It errs toward support: a false positive costs one supportive reply, a
//  miss costs much more. It never diagnoses; it only decides whether a
//  surface may analyze the text.
//
//  Sentence-embedding similarity was tried for indirect wording and rejected:
//  with NLEmbedding, "I can't wait for this project to be over" sat closer to
//  the crisis seeds than most real indirect cues, so no threshold separated
//  them. Indirect wording is listed explicitly instead.
//

import Foundation

public enum JournalRiskClassifier {

    /// Safety level for one piece of text.
    public static func level(for text: String) -> JournalSafetyLevel {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return .none }
        if matches(highRiskPhrases, in: normalized) { return .highRiskExcluded }
        if matches(moderateConcernPhrases, in: normalized) { return .moderateConcern }
        if matches(mildDistressPhrases, in: normalized) { return .mildDistress }
        return .none
    }

    /// The highest safety level across several texts.
    public static func level<Texts: Sequence>(forAll texts: Texts) -> JournalSafetyLevel where Texts.Element == String {
        texts.reduce(JournalSafetyLevel.none) { Swift.max($0, level(for: $1)) }
    }

    /// How a surface should respond to the text under `policy`.
    public static func responseMode(
        for text: String,
        policy: SensitiveDomainPolicy = .standard
    ) -> SensitiveResponseMode {
        policy.responseMode(for: level(for: text))
    }

    // MARK: - Phrases

    /// Direct and indirect references to suicide or self-harm.
    static let highRiskPhrases: [String] = [
        "kill myself", "killing myself", "kill my self",
        "suicide", "suicidal",
        "end my life", "ending my life", "end it all",
        "take my own life", "taking my own life",
        "self harm", "self-harm", "selfharm", "harm myself", "hurt myself", "hurting myself",
        "cut myself", "cutting myself",
        "want to die", "wanna die", "wish i was dead", "wish i were dead", "better off dead",
        "better off without me", "everyone would be better off",
        "if i wasn't here", "if i weren't here", "if i was gone", "if i were gone",
        "no reason to live", "nothing to live for", "not worth living",
        "don't want to live", "do not want to live", "don't want to be alive", "do not want to be alive",
        "don't want to wake up", "never wake up again", "can't go on living",
        "disappear forever",
    ]

    /// Hopelessness and indirect wording that is often, but not always, about risk.
    static let moderateConcernPhrases: [String] = [
        "hopeless", "worthless",
        "can't cope", "cannot cope", "can't take it anymore", "can't do this anymore",
        "no way out", "ending things", "give up on everything",
        "nobody would notice", "nobody would care", "no one would notice", "no one would care",
        "what's the point of anything", "no point in anything", "empty inside",
    ]

    /// Ordinary distress: the surface softens and skips probing questions.
    static let mildDistressPhrases: [String] = [
        "overwhelmed", "exhausted", "panic", "panicked", "panicking", "burned out", "burnt out", "breaking down",
    ]

    // MARK: - Matching

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func matches(_ phrases: [String], in normalized: String) -> Bool {
        phrases.contains { phrase in
            var searchRange = normalized.startIndex..<normalized.endIndex
            while let range = normalized.range(of: phrase, range: searchRange) {
                if isWordBoundary(before: range.lowerBound, in: normalized),
                   isWordBoundary(after: range.upperBound, in: normalized) {
                    return true
                }
                searchRange = range.upperBound..<normalized.endIndex
            }
            return false
        }
    }

    private static func isWordBoundary(before index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        return !text[text.index(before: index)].isLetter
    }

    private static func isWordBoundary(after index: String.Index, in text: String) -> Bool {
        guard index < text.endIndex else { return true }
        return !text[index].isLetter
    }
}
