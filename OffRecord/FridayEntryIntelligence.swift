//
//  FridayEntryIntelligence.swift
//  OffRecord
//
//  Whether Friday may write about an entry at all: Friday is on, the entry
//  isn't kept out of Friday, and the entry isn't high-risk. Generated titles,
//  Go Deeper questions, and the chat's journal tools all ask here first.
//

import Foundation
import JournalFoundation
import SemanticMemoryKit

enum FridayEntryIntelligence {
    /// The global Friday switch. Read straight from its stored key so this file
    /// doesn't depend on the settings type; missing means on.
    static var isFridayEnabled: Bool {
        UserDefaults.standard.object(forKey: "offrecord_friday_enabled") as? Bool ?? true
    }

    /// Whether this entry may be searched, cited, or written about by Friday.
    /// Per-entry "Keep out of Friday" plugs in here.
    static func permitsAssistantEvidence(_ entry: DiaryEntry) -> Bool {
        true
    }

    /// Friday is on and the entry isn't kept out of Friday.
    static func isEligible(_ entry: DiaryEntry) -> Bool {
        isFridayEnabled && permitsAssistantEvidence(entry)
    }

    /// Whether Friday may generate text (a title, a question) about this entry's text.
    static func mayGenerate(about entry: DiaryEntry, text: String) -> Bool {
        isEligible(entry) && mayGenerate(about: text)
    }

    /// High-risk text is never sent to the model.
    static func mayGenerate(about text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && JournalRiskClassifier.level(for: trimmed) != .highRiskExcluded
    }
}

/// What a model sees about one entry: its text (capped) and the names and
/// topics already found in it, so prompts and validation agree on what is
/// "in the entry".
struct EntryGenerationContext: Equatable, Sendable {
    /// Long entries are cut here; the model's context window is small.
    static let maximumCharacters = 1_500

    let text: String
    let mood: Mood
    let names: [String]
    let topics: [String]

    init(text: String, mood: Mood) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = String(trimmed.prefix(Self.maximumCharacters))
        self.text = capped
        self.mood = mood
        let names = EntityExtractor.namedEntities(in: capped).map(\.text)
        self.names = names
        self.topics = EntryInsightAnalyzer.topics(in: capped, limit: 6).filter { !names.contains($0) }
    }

    /// The prompt block shared by every entry-level generator.
    var promptBlock: String {
        """
        Entry:
        \(text)

        Mood: \(mood == .none ? "not set" : mood.displayName.lowercased())
        Names in the entry: \(names.isEmpty ? "none" : names.joined(separator: ", "))
        Topics in the entry: \(topics.isEmpty ? "none" : topics.map { $0.lowercased() }.joined(separator: ", "))
        """
    }
}
