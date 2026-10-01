//
//  TextAnalysis.swift
//  SemanticMemoryKit
//
//  The one sentiment scorer and the one entity/topic extractor that every
//  journal surface shares. Before this file, five call sites in OffRecord
//  each ran their own NLTagger with slightly different options; they now
//  delegate here so a profile, an insight, and a weekly reflection read the
//  same text the same way.
//

import Foundation
import NaturalLanguage

// MARK: - Sentiment

public enum SentimentScorer {
    /// NaturalLanguage sentiment for `text`, from -1 (negative) to 1 (positive).
    ///
    /// Every paragraph is scored and the results are averaged by length, so a
    /// multi-block entry isn't judged by its first line alone. Returns nil for
    /// empty text or when the tagger has no score.
    public static func languageScore(for text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = trimmed
        var weightedTotal = 0.0
        var totalWeight = 0.0
        tagger.enumerateTags(in: trimmed.startIndex..<trimmed.endIndex, unit: .paragraph, scheme: .sentimentScore, options: []) { tag, range in
            let paragraph = trimmed[range].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !paragraph.isEmpty, let tag, let value = Double(tag.rawValue) else { return true }
            let weight = Double(paragraph.count)
            weightedTotal += value * weight
            totalWeight += weight
            return true
        }
        guard totalWeight > 0 else { return nil }
        return max(-1, min(1, weightedTotal / totalWeight))
    }

    /// `languageScore(for:)`, or 0 when there's nothing to score.
    public static func score(_ text: String) -> Double {
        languageScore(for: text) ?? 0
    }

    /// Mood-first keyword score used by reflection surfaces: the mood the
    /// person picked wins; otherwise a small word list decides. Deterministic
    /// across platforms (no NaturalLanguage model involved), from -0.8 to 0.8.
    public static func moodWeightedScore(text: String, mood: String?) -> Double {
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
}

// MARK: - Entities and topics

/// A name NaturalLanguage found in text.
public struct NamedEntity: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case person, place, organization
    }

    public let text: String
    public let kind: Kind

    public init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }
}

/// One word with its part of speech, for callers that rank their own topics.
public struct TaggedWord: Hashable, Sendable {
    public enum LexicalKind: Hashable, Sendable {
        case noun, verb, adjective, adverb, other
    }

    /// The word as written, without surrounding punctuation.
    public let text: String
    /// Nil when no part-of-speech model is available (some simulators).
    public let lexicalKind: LexicalKind?
    /// Set only for nouns that NaturalLanguage tags as a name.
    public let nameKind: NamedEntity.Kind?
    /// Whether the word sits inside a sentence rather than starting one, so a capital marks a name.
    public let isMidSentence: Bool

    public init(text: String, lexicalKind: LexicalKind?, nameKind: NamedEntity.Kind?, isMidSentence: Bool) {
        self.text = text
        self.lexicalKind = lexicalKind
        self.nameKind = nameKind
        self.isMidSentence = isMidSentence
    }
}

public enum EntityExtractor {
    /// Function words and filler that never make a topic.
    public static let commonWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
        "be", "have", "has", "had", "do", "does", "did", "will", "would",
        "could", "should", "may", "might", "must", "shall", "can", "need",
        "this", "that", "these", "those", "i", "you", "he", "she", "it",
        "we", "they", "what", "which", "who", "when", "where", "why", "how",
        "all", "each", "every", "both", "few", "more", "most", "other",
        "some", "such", "no", "nor", "not", "only", "own", "same", "so",
        "than", "too", "very", "just", "also", "now", "here", "there",
        "about", "like", "really", "much", "still", "well", "back", "even",
        "then", "thing", "things", "know", "think", "want", "get", "got",
        "going", "make", "made", "come", "came", "take", "took", "give",
        "gave", "tell", "told", "say", "said", "good", "time", "day"
    ]

    /// Every name in `text`, in reading order, repeats included (a knowledge
    /// graph counts each mention). Single letters are skipped.
    public static func nameOccurrences(in text: String) -> [NamedEntity] {
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var result: [NamedEntity] = []
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            guard let kind = tag.flatMap(NamedEntity.Kind.init(nameTag:)) else { return true }
            let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count > 1 { result.append(NamedEntity(text: value, kind: kind)) }
            return true
        }
        return result
    }

    /// Each distinct name once, in order of first mention.
    public static func namedEntities(in text: String) -> [NamedEntity] {
        var seen = Set<NamedEntity>()
        return nameOccurrences(in: text).filter { seen.insert($0).inserted }
    }

    /// Each distinct personal name once, in order of first mention.
    public static func personalNames(in text: String) -> [String] {
        var seen = Set<String>()
        return nameOccurrences(in: text)
            .filter { $0.kind == .person }
            .map(\.text)
            .filter { seen.insert($0).inserted }
    }

    /// Lowercased nouns in reading order, repeats included. Empty when no
    /// part-of-speech model is available.
    public static func nouns(
        in text: String,
        minimumLength: Int = 4,
        excluding stopWords: Set<String> = commonWords
    ) -> [String] {
        words(in: text).compactMap { word in
            guard word.lexicalKind == .noun else { return nil }
            let lower = word.text.lowercased()
            guard lower.count >= minimumLength, !stopWords.contains(lower) else { return nil }
            return lower
        }
    }

    /// Every word in `text` with its part of speech, in reading order.
    public static func words(in text: String) -> [TaggedWord] {
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = text
        if let language = NLLanguageRecognizer.dominantLanguage(for: text) {
            tagger.setLanguage(language, range: text.startIndex..<text.endIndex)
        }
        var result: [TaggedWord] = []
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            let original = String(text[range]).trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard !original.isEmpty else { return true }
            let lexicalKind = tag.map(TaggedWord.LexicalKind.init(lexicalTag:))
            var nameKind: NamedEntity.Kind?
            if lexicalKind == .noun {
                nameKind = tagger.tag(at: range.lowerBound, unit: .word, scheme: .nameType).0
                    .flatMap(NamedEntity.Kind.init(nameTag:))
            }
            result.append(TaggedWord(
                text: original,
                lexicalKind: lexicalKind,
                nameKind: nameKind,
                isMidSentence: isMidSentence(range.lowerBound, in: text)
            ))
            return true
        }
        return result
    }

    /// Whether the character at `index` sits inside a sentence rather than starting one.
    public static func isMidSentence(_ index: String.Index, in text: String) -> Bool {
        var cursor = index
        while cursor > text.startIndex {
            cursor = text.index(before: cursor)
            let character = text[cursor]
            if character.isWhitespace { continue }
            return !".!?\"“”".contains(character)
        }
        return false
    }
}

private extension NamedEntity.Kind {
    init?(nameTag: NLTag) {
        switch nameTag {
        case .personalName: self = .person
        case .placeName: self = .place
        case .organizationName: self = .organization
        default: return nil
        }
    }
}

private extension TaggedWord.LexicalKind {
    init(lexicalTag: NLTag) {
        switch lexicalTag {
        case .noun: self = .noun
        case .verb: self = .verb
        case .adjective: self = .adjective
        case .adverb: self = .adverb
        default: self = .other
        }
    }
}
