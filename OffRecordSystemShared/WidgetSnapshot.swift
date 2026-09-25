//
//  WidgetSnapshot.swift
//  OffRecordSystemShared
//
//  Privacy-safe journal summary the app writes to the App Group for widgets.
//  It holds dates, mood raw values, and counts only: never journal text,
//  transcripts, photo names, or audio file names.
//

import Foundation
import os.log

private let snapshotLogger = Logger(subsystem: "com.singularity.offrecord", category: "WidgetSnapshot")

struct WidgetSnapshot: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = WidgetSnapshot.currentVersion
    /// Journal days keyed by `WidgetDayKey` ("yyyy-MM-dd" in the local calendar).
    /// The value is the day's mood raw value, or an empty string when the day
    /// has an entry without a mood.
    var days: [String: String]
    /// Number of started journal entries.
    var totalEntries: Int
    /// Metadata for the day named by `todayKey`, valid only while that day is today.
    var todayKey: String?
    var todayWordCount: Int
    var todayHasVoice: Bool

    static let empty = WidgetSnapshot(days: [:], totalEntries: 0, todayKey: nil, todayWordCount: 0, todayHasVoice: false)

    func hasEntry(on date: Date, calendar: Calendar = .current) -> Bool {
        days[WidgetDayKey.key(for: date, calendar: calendar)] != nil
    }

    /// The mood raw value for a day, nil when there is no entry or no mood.
    func mood(on date: Date, calendar: Calendar = .current) -> String? {
        guard let raw = days[WidgetDayKey.key(for: date, calendar: calendar)], !raw.isEmpty else { return nil }
        return raw
    }

    /// Consecutive journaling days ending today, or yesterday when today is still open.
    func streak(asOf date: Date, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: date)
        if !hasEntry(on: day, calendar: calendar) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while hasEntry(on: day, calendar: calendar) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// Mood counts over the seven days ending on `date`.
    func weekMoodCounts(asOf date: Date, calendar: Calendar = .current) -> [String: Int] {
        let start = calendar.startOfDay(for: date)
        var counts: [String: Int] = [:]
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: start),
                  let mood = mood(on: day, calendar: calendar) else { continue }
            counts[mood, default: 0] += 1
        }
        return counts
    }

    func todayWordCount(asOf date: Date, calendar: Calendar = .current) -> Int {
        todayKey == WidgetDayKey.key(for: date, calendar: calendar) ? todayWordCount : 0
    }

    func todayHasVoice(asOf date: Date, calendar: Calendar = .current) -> Bool {
        todayKey == WidgetDayKey.key(for: date, calendar: calendar) && todayHasVoice
    }
}

enum WidgetDayKey {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

enum WidgetSnapshotStore {
    static let appGroupIdentifier = "group.com.singularity.offrecord"
    static let fileName = "WidgetSnapshot.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
            guard snapshot.version == WidgetSnapshot.currentVersion else { return nil }
            return snapshot
        } catch {
            snapshotLogger.error("Widget snapshot unreadable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Writes the snapshot and reports whether the stored bytes changed.
    @discardableResult
    static func save(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = fileURL else {
            snapshotLogger.error("App Group container unavailable; widget snapshot not written.")
            return false
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)
            if let existing = try? Data(contentsOf: url), existing == data {
                return false
            }
            // Readable after first unlock so Lock Screen widgets can render metadata.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            snapshotLogger.error("Widget snapshot write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
