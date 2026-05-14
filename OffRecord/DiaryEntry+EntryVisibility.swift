import Foundation

extension DiaryEntry {
    var startedEntryWordCount: Int {
        let text = (self.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return 0 }
        return text.split { $0.isWhitespace || $0.isNewline }.count
    }

    var hasStartedEntryAudio: Bool {
        let fileName = (value(forKey: "audioFileName") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !fileName.isEmpty || duration > 0
    }

    var hasStartedEntryPhotos: Bool {
        (photos?.count ?? 0) > 0
    }

    var hasStartedEntryMood: Bool {
        guard let moodString = (value(forKey: "mood") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let mood = Mood(rawValue: moodString) else {
            return false
        }
        return mood != .none
    }

    var isStartedEntry: Bool {
        startedEntryWordCount > 0
            || hasStartedEntryAudio
            || hasStartedEntryPhotos
            || hasStartedEntryMood
    }
}

extension Sequence where Element == DiaryEntry {
    var startedEntries: [DiaryEntry] {
        filter(\.isStartedEntry)
    }
}
