//
//  FridayGeneratedTextCache.swift
//  OffRecord
//
//  Model-written text that must read the same every time it's shown: Go
//  Deeper questions (keyed by a hash of the entry text) and entry titles
//  (keyed by entry ID and last edit). Stored next to the chat history in
//  Application Support/FridayLocal with complete file protection, excluded
//  from backups, and never in Core Data. An empty value records "the model
//  was asked and its answer failed validation", so the fallback stays put
//  instead of a second attempt changing what the person saw.
//

import Foundation
import SemanticMemoryKit

@MainActor
final class FridayGeneratedTextStore {
    struct Item: Codable, Equatable {
        var value: String
        var storedAt: Date
    }

    private let file: FridayProtectedJSONFile<[String: Item]>?
    private let capacity: Int
    private var items: [String: Item]?
    /// Bumped by `removeAll()`, so an answer that was in flight during an erase is dropped.
    private(set) var generation = 0

    /// - Parameter fileName: nil keeps the store in memory only (UI tests, unit tests).
    init(fileName: String?, capacity: Int) {
        self.file = fileName.map { FridayProtectedJSONFile<[String: Item]>(fileName: $0) }
        self.capacity = capacity
    }

    /// The stored value for `key`. `""` means "fall back"; nil means never asked.
    func value(for key: String) -> String? {
        loadedItems()[key]?.value
    }

    /// Stores `value`, dropping other keys that start with `replacingPrefix`
    /// (an entry's older titles) and the oldest items beyond capacity.
    func set(_ value: String, for key: String, replacingPrefix prefix: String? = nil) {
        var current = loadedItems()
        if let prefix {
            for existing in current.keys where existing.hasPrefix(prefix) && existing != key {
                current.removeValue(forKey: existing)
            }
        }
        current[key] = Item(value: value, storedAt: Date())
        if current.count > capacity {
            let overflow = current.sorted { $0.value.storedAt < $1.value.storedAt }.prefix(current.count - capacity)
            for (key, _) in overflow { current.removeValue(forKey: key) }
        }
        items = current
        file?.save(current)
    }

    var count: Int { loadedItems().count }

    func removeAll() {
        items = [:]
        generation += 1
        file?.delete()
    }

    private func loadedItems() -> [String: Item] {
        if let items { return items }
        let loaded = file?.load() ?? [:]
        items = loaded
        return loaded
    }
}

@MainActor
enum FridayGeneratedTextCache {
    private static var isEphemeral: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-UITesting") || arguments.contains("-ScreenshotMode")
    }

    static let questions = FridayGeneratedTextStore(
        fileName: isEphemeral ? nil : "friday-go-deeper-questions.json",
        capacity: 400
    )

    static let titles = FridayGeneratedTextStore(
        fileName: isEphemeral ? nil : "friday-entry-titles.json",
        capacity: 2_000
    )

    /// Forgets every generated question and title. Call when Friday is turned
    /// off or the journal is erased.
    static func removeAll() {
        questions.removeAll()
        titles.removeAll()
    }

    /// Question cache key: the entry's text and mood, never the text itself.
    static func questionKey(text: String, mood: Mood) -> String {
        TextSignals.hash(text.trimmingCharacters(in: .whitespacesAndNewlines)) + "|" + mood.rawValue
    }

    /// Title cache key: one entry at one edit.
    static func titleKey(entryID: UUID, updatedAt: Date?) -> String {
        "\(entryID.uuidString)|\(Int((updatedAt ?? .distantPast).timeIntervalSinceReferenceDate))"
    }
}
