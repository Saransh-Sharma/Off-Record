import Foundation

extension FridayAssistantEngine: @unchecked Sendable {}

private actor FridayLearningWorker {
    static let shared = FridayLearningWorker()

    private let assistant = FridayAssistantEngine.shared

    func processEntry(text: String, mood: String?, date: Date, duration: Double) {
        assistant.processEntry(text: text, mood: mood, date: date, duration: duration)
    }

    func reprocessEditedEntry(oldText: String, newText: String, mood: String?, date: Date, duration: Double) {
        assistant.reprocessEditedEntry(
            oldText: oldText,
            newText: newText,
            mood: mood,
            date: date,
            duration: duration
        )
    }
}

enum EntryLearningPipeline {
    static func processSavedEntry(
        text: String,
        mood: String?,
        date: Date,
        duration: Double
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        PerformanceSignposts.event("FridayProcessingScheduled")
        Task(priority: .utility) {
            let token = PerformanceSignposts.begin("FridayProcessing")
            await FridayLearningWorker.shared.processEntry(
                text: trimmed,
                mood: mood,
                date: date,
                duration: duration
            )
            PerformanceSignposts.end(token)
        }
    }

    static func reprocessEditedEntry(
        oldText: String,
        newText: String,
        mood: String?,
        date: Date,
        duration: Double
    ) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        PerformanceSignposts.event("FridayReprocessingScheduled")
        Task(priority: .utility) {
            let token = PerformanceSignposts.begin("FridayReprocessing")
            await FridayLearningWorker.shared.reprocessEditedEntry(
                oldText: oldText,
                newText: trimmed,
                mood: mood,
                date: date,
                duration: duration
            )
            PerformanceSignposts.end(token)
        }
    }

    static func upsertSemanticEntry(_ entry: DiaryEntry) {
        guard let record = IndexableEntry(entry: entry) else { return }
        upsertSemanticRecord(record)
    }

    static func upsertSemanticRecord(_ record: IndexableEntry) {
        PerformanceSignposts.event("SemanticMemoryUpsertScheduled")
        Task(priority: .utility) {
            let token = PerformanceSignposts.begin("SemanticMemoryUpsert")
            await SemanticMemoryIndexController.shared.upsertRecord(record)
            PerformanceSignposts.end(token)
        }
    }
}
