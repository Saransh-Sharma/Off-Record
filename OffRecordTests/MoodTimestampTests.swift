import CoreData
import Foundation
import Testing
@testable import OffRecord

/// A mood picked now must become the entry's mood, whatever the time of day.
@MainActor
struct MoodTimestampTests {
    @Test func changingLastNightsMoodNextMorningBecomesTheEntryMood() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let lastNight = makeDate(hour: 21)
        let entry = makeEntry(on: lastNight, in: context)
        JournalBlockTimelineStore.appendMoodBlock(mood: .happy, createdAt: lastNight, to: entry, in: context)
        JournalBlockTimelineStore.appendTextBlock(
            text: "Long day.",
            createdAt: lastNight.addingTimeInterval(5 * 60),
            to: entry,
            in: context
        )
        #expect(entry.value(forKey: "mood") as? String == Mood.happy.rawValue)

        // The entry detail stamps a new block with the entry's day and the current time: 08:00.
        let sameDayMorning = makeDate(hour: 8)
        let createdAt = JournalBlockTimelineStore.moodTimestamp(proposed: sameDayMorning, for: entry)
        JournalBlockTimelineStore.appendMoodBlock(mood: .sad, createdAt: createdAt, to: entry, in: context)
        try context.save()

        #expect(entry.value(forKey: "mood") as? String == Mood.sad.rawValue)
        let last = try #require(JournalBlockTimelineStore.blocks(for: entry).last)
        #expect(last.blockKind == .mood)
        #expect(last.moodValue == Mood.sad.rawValue)
        #expect(Calendar.current.isDate(createdAt, inSameDayAs: lastNight))
    }

    @Test func moodPickedAfterEveryBlockKeepsItsOwnTime() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let morning = makeDate(hour: 8)
        let entry = makeEntry(on: morning, in: context)
        JournalBlockTimelineStore.appendMoodBlock(mood: .happy, createdAt: morning, to: entry, in: context)

        let evening = makeDate(hour: 19)
        #expect(JournalBlockTimelineStore.moodTimestamp(proposed: evening, for: entry) == evening)
    }

    @Test func emptyEntryKeepsTheProposedTime() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let noon = makeDate(hour: 12)
        let entry = makeEntry(on: noon, in: context)

        #expect(JournalBlockTimelineStore.moodTimestamp(proposed: noon, for: entry) == noon)
    }

    private func makeEntry(on date: Date, in context: NSManagedObjectContext) -> DiaryEntry {
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = date
        entry.createdAt = date
        entry.updatedAt = date
        return entry
    }

    private func makeDate(hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar.current
        components.year = 2036
        components.month = 5
        components.day = 24
        components.hour = hour
        return components.date!
    }
}
