import CoreData
import Foundation

enum DiaryEntryTranscriptionStatus: String {
    case none
    case processing
    case completed
    case failed
}

extension DiaryEntry {
    static var startedEntryPredicate: NSPredicate {
        NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "text != nil AND text != ''"),
            NSPredicate(format: "duration > 0"),
            NSPredicate(format: "audioFileName != nil AND audioFileName != ''"),
            NSPredicate(format: "mood != nil AND mood != '' AND mood != %@", Mood.none.rawValue),
            NSPredicate(format: "photos.@count > 0")
        ])
    }

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
        let moodString = (value(forKey: "mood") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !moodString.isEmpty && moodString != Mood.none.rawValue
    }

    var entryTranscriptionStatus: DiaryEntryTranscriptionStatus {
        get {
            let rawStatus = (value(forKey: "transcriptionStatus") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return DiaryEntryTranscriptionStatus(rawValue: rawStatus) ?? .none
        }
        set {
            setValue(newValue == .none ? nil : newValue.rawValue, forKey: "transcriptionStatus")
        }
    }

    var isTranscriptionProcessing: Bool {
        entryTranscriptionStatus == .processing
    }

    func shouldShowTranscriptionSpinner(displayText: String?) -> Bool {
        let trimmedText = (displayText ?? text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty && isTranscriptionProcessing
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
