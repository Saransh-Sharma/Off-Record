//
//  EntryFollowUpQuestion.swift
//  OffRecord
//
//  Deterministic, on-device "go deeper" questions grounded in what the
//  person just wrote: the people and topics they mentioned and their mood.
//

import Foundation
import SemanticMemoryKit

enum EntryFollowUpQuestion {
    /// Returns a follow-up question for `text`, avoiding `excluding` when alternatives exist.
    static func make(text: String, mood: Mood, excluding previous: String? = nil) -> String {
        let candidates = questions(text: text, mood: mood)
        let fresh = candidates.filter { $0 != previous }
        let pool = fresh.isEmpty ? candidates : fresh
        // Deterministic per entry text so reopening shows the same first question.
        let seed = stableSeed(text) &+ stableSeed(previous ?? "")
        return pool[Int(seed % UInt64(pool.count))]
    }

    private static func stableSeed(_ value: String) -> UInt64 {
        value.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
    }

    static func questions(text: String, mood: Mood) -> [String] {
        var result: [String] = []
        let people = TextSignals.extractEntities(from: text)
            .filter { $0.first?.isUppercase == true && $0.count > 1 }
            .prefix(2)
        let topics = TextSignals.extractTopics(from: text, limit: 3)
            .filter { $0.count > 3 }

        for person in people {
            result.append(String(localized: "What do you wish \(person) knew about how this felt?"))
            result.append(String(localized: "What does your time with \(person) tend to bring out in you?"))
        }
        if let topic = topics.first {
            result.append(String(localized: "What’s still on your mind about \(topic)?"))
            result.append(String(localized: "If \(topic) went the way you hoped, what would change?"))
        }

        switch mood {
        case .tired, .sad, .anxious:
            result.append(String(localized: "What would make tomorrow easier?"))
            result.append(String(localized: "What do you need right now?"))
        case .angry:
            result.append(String(localized: "Is this feeling pointing to a boundary?"))
        case .happy, .grateful, .excited:
            result.append(String(localized: "What made this possible?"))
            result.append(String(localized: "Who would you tell about this?"))
        case .calm:
            result.append(String(localized: "What helped you feel settled today?"))
        case .none:
            break
        }

        result.append(String(localized: "What part of this do you want to understand?"))
        result.append(String(localized: "What would you tell a friend who wrote this?"))
        return result
    }
}
