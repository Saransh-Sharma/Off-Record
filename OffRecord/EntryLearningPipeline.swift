import Foundation

private actor FridayLearningWorker {
    static let shared = FridayLearningWorker()

    func processEntry(text: String, mood: String?, date: Date, duration: Double) async {
        await MainActor.run {
            FridayAssistantEngine.shared.processEntry(text: text, mood: mood, date: date, duration: duration)
        }
    }
}

enum EntryLearningPipeline {
    @MainActor
    static func processSavedEntry(
        text: String,
        mood: String?,
        date: Date,
        duration: Double
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Normally Friday's profile is rebuilt from the journal after every save.
        // Fixture runs (UI tests, screenshots) don't start the rebuilder, so they
        // keep learning one entry at a time.
        if FridayProfileRebuilder.shared.isActive {
            FridayProfileRebuilder.shared.scheduleRefresh()
            return
        }

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
