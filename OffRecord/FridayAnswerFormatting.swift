//
//  FridayAnswerFormatting.swift
//  OffRecord
//
//  Pure, deterministic helpers that turn an evidence-backed answer into what
//  the chat shows: citation-marked segments, an evidence-strength label, and
//  contextual follow-up questions. Nothing here touches the network.
//

import SwiftUI

// MARK: - Follow-ups

struct FridayFollowUp: Identifiable, Equatable, Hashable {
    let title: String
    let prompt: String
    let question: FridayQuestion?

    var id: String { prompt.lowercased() }

    var accessibilityID: String {
        question?.accessibilityID ?? String(TextSignals.hash(prompt.lowercased()).prefix(10))
    }

    init(title: String, prompt: String, question: FridayQuestion? = nil) {
        self.title = title
        self.prompt = prompt
        self.question = question
    }

    init(question: FridayQuestion) {
        self.init(title: question.question, prompt: question.question, question: question)
    }
}

enum FridayFollowUpBuilder {
    static let maximumCount = 3
    static let minimumCount = 2

    /// Suggests 2–3 follow-ups from the answer's own evidence: people or themes
    /// the cited entries mention, the mood they share, and how far back they go.
    /// Remaining slots are filled with suggested questions not yet asked.
    static func followUps(
        question: String,
        evidence: [EvidenceReference],
        knownNames: [(match: String, display: String)],
        askedPrompts: Set<String>,
        fallbackQuestions: [FridayQuestion],
        calendar: Calendar = .current
    ) -> [FridayFollowUp] {
        var results: [FridayFollowUp] = []
        let loweredQuestion = question.lowercased()
        let evidenceText = evidence.map { "\($0.snippet) \($0.chunkText)" }.joined(separator: " ").lowercased()

        func append(_ followUp: FridayFollowUp) {
            let key = followUp.id
            // Older history sent a suggested question's rawValue as the message text.
            let legacyKey = followUp.question?.rawValue.lowercased()
            guard results.count < maximumCount,
                  !askedPrompts.contains(key),
                  !(legacyKey.map { askedPrompts.contains($0) } ?? false),
                  key != loweredQuestion,
                  !results.contains(where: { $0.id == key }) else { return }
            results.append(followUp)
        }

        if !evidence.isEmpty {
            // A person or theme that shows up in the cited entries but wasn't in the question.
            // The prompt keeps the name as written so retrieval can find it; the title honors renames.
            if let name = knownNames.first(where: { name in
                let lowered = name.match.lowercased()
                return lowered.count > 2 && containsWord(lowered, in: evidenceText) && !containsWord(lowered, in: loweredQuestion)
            }) {
                append(FridayFollowUp(
                    title: String(localized: "More about \(name.display)", comment: "Follow-up chip; the placeholder is a person, place, or theme"),
                    prompt: String(localized: "What else have I written about \(name.match)?")
                ))
            }

            // The mood the cited entries share most.
            let moods = evidence.compactMap { $0.mood?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
            if let mood = Dictionary(grouping: moods, by: { $0 })
                .max(by: { $0.value.count == $1.value.count ? $0.key > $1.key : $0.value.count < $1.value.count })?.key,
               !containsWord(mood, in: loweredQuestion) {
                append(FridayFollowUp(
                    title: String(localized: "Other \(mood) days", comment: "Follow-up chip; the placeholder is a mood, like happy"),
                    prompt: String(localized: "When else did I feel \(mood)?", comment: "The placeholder is a mood, like happy")
                ))
            }

            // How far back the evidence reaches.
            let dates = evidence.map(\.date).sorted()
            if let earliest = dates.first, let latest = dates.last,
               (calendar.dateComponents([.day], from: earliest, to: latest).day ?? 0) >= 7 {
                let month = earliest.formatted(.dateTime.month(.wide))
                append(FridayFollowUp(
                    title: String(localized: "What’s changed since \(month)?", comment: "Follow-up chip; the placeholder is a month name"),
                    prompt: String(localized: "How has this changed since \(month)?", comment: "The placeholder is a month name")
                ))
            } else {
                append(FridayFollowUp(
                    title: String(localized: "What helped before?"),
                    prompt: String(localized: "What helped me when I felt like this before?")
                ))
            }
        }

        for fallback in fallbackQuestions where results.count < maximumCount {
            append(FridayFollowUp(question: fallback))
        }

        return results
    }

    private static func containsWord(_ word: String, in text: String) -> Bool {
        guard let range = text.range(of: word) else { return false }
        let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
        let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
        let isBoundary: (Character?) -> Bool = { character in
            guard let character else { return true }
            return !character.isLetter && !character.isNumber
        }
        if isBoundary(before) && isBoundary(after) { return true }
        // Try later occurrences.
        let rest = String(text[range.upperBound...])
        return containsWord(word, in: rest)
    }
}

// MARK: - Evidence strength

enum FridayEvidenceStrength: Equatable {
    case strong(entries: Int)
    case some(entries: Int)
    case tentative(entries: Int)
    case overallPatterns

    static func assess(confidence: Double?, evidence: [EvidenceReference]) -> FridayEvidenceStrength? {
        let entries = Set(evidence.map(\.entryID)).count
        let confidence = confidence ?? 0
        guard entries > 0 else {
            return confidence > 0 ? .overallPatterns : nil
        }
        if confidence >= 0.7 && entries >= 3 { return .strong(entries: entries) }
        if confidence >= 0.5 && entries >= 2 { return .some(entries: entries) }
        return .tentative(entries: entries)
    }

    var title: String {
        switch self {
        case .strong(let entries): return String(localized: "Strong evidence · \(Self.entryText(entries))", comment: "The placeholder is an entry count, like “4 entries”")
        case .some(let entries): return String(localized: "Some evidence · \(Self.entryText(entries))", comment: "The placeholder is an entry count, like “4 entries”")
        case .tentative(let entries): return String(localized: "Limited evidence · \(Self.entryText(entries))", comment: "The placeholder is an entry count, like “4 entries”")
        case .overallPatterns: return String(localized: "From your overall patterns")
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .strong(let entries): return String(localized: "Strong evidence, based on \(Self.entryText(entries))")
        case .some(let entries): return String(localized: "Some evidence, based on \(Self.entryText(entries))")
        case .tentative(let entries): return String(localized: "Limited evidence, based on \(Self.entryText(entries))")
        case .overallPatterns: return String(localized: "Based on your overall patterns")
        }
    }

    var systemImage: String {
        switch self {
        case .strong: return "checkmark.seal.fill"
        case .some: return "circle.lefthalf.filled"
        case .tentative: return "questionmark.circle"
        case .overallPatterns: return "waveform.path.ecg"
        }
    }

    var style: OffRecordReadableTintStyle {
        switch self {
        case .strong: return .privacy
        case .some: return .friday
        case .tentative: return .highlight
        case .overallPatterns: return .neutral
        }
    }

    private static func entryText(_ count: Int) -> String {
        String(AttributedString(localized: "^[\(count) entry](inflect: true)").characters)
    }
}

// MARK: - Citation-marked answer text

struct FridayAnswerSegment: Equatable {
    let text: String
    /// 1-based citation numbers matching the evidence chips.
    let citations: [Int]
}

enum FridayAnswerComposer {
    /// Splits the summary into sentences (for progressive reveal) and attaches
    /// citation numbers to each observation from its evidence IDs.
    static func segments(
        summary: String,
        observations: [EvidenceObservation],
        evidence: [EvidenceReference]
    ) -> [FridayAnswerSegment] {
        let indexByID = Dictionary(evidence.enumerated().map { ($0.element.id, $0.offset + 1) }, uniquingKeysWith: { first, _ in first })
        var segments = sentences(in: summary).map { FridayAnswerSegment(text: $0, citations: []) }
        for observation in observations {
            let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let citations = Array(Set(observation.evidenceIDs.compactMap { indexByID[$0] })).sorted()
            segments.append(FridayAnswerSegment(text: text, citations: citations))
        }
        return segments
    }

    static func plainText(_ segments: [FridayAnswerSegment]) -> String {
        segments.map(\.text).joined(separator: " ")
    }

    static func attributedText(
        _ segments: [FridayAnswerSegment],
        revealedCount: Int,
        textColor: Color,
        markerColor: Color
    ) -> AttributedString {
        var result = AttributedString()
        for (index, segment) in segments.enumerated() {
            let isRevealed = index < revealedCount
            if index > 0 {
                result += AttributedString(" ")
            }
            var body = AttributedString(segment.text)
            body.foregroundColor = isRevealed ? textColor : .clear
            result += body

            for number in segment.citations {
                var marker = AttributedString("\u{2009}[\(number)]")
                marker.font = OffRecordTypography.annotation.weight(.semibold)
                marker.baselineOffset = 5
                marker.foregroundColor = isRevealed ? markerColor : .clear
                result += marker
            }
        }
        return result
    }

    static func sentences(in text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var sentences: [String] = []
        trimmed.enumerateSubstrings(in: trimmed.startIndex..<trimmed.endIndex, options: [.bySentences, .localized]) { substring, _, _, _ in
            if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        return sentences.isEmpty ? [trimmed] : sentences
    }
}
