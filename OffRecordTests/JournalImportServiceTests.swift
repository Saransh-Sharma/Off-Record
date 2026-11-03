import CoreData
import Foundation
import Testing
@testable import OffRecord

/// Saving imported entries: one entry per day, time order, the photo limit, and no duplicates on re-import.
@MainActor
@Suite(.serialized)
struct JournalImportServiceTests {

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    private func day(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(from: DateComponents(year: 2025, month: 3, day: 4, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: dayOffset, to: base)!
    }

    private func entries(in context: NSManagedObjectContext) throws -> [DiaryEntry] {
        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: true)]
        return try context.fetch(request)
    }

    private func preview(_ drafts: [ImportedEntryDraft], files: [String: Data] = [:], context: NSManagedObjectContext) -> JournalImportPreview {
        JournalImportService.makePreview(
            format: .markdown,
            source: InMemoryImportSource(files: files),
            parsed: JournalImportParseResult(drafts: drafts, skipped: []),
            context: context
        )
    }

    @Test func sameDayDraftsBecomeBlocksOfOneEntryInTimeOrder() async throws {
        let context = makeContext()
        let existing = try DiaryEntryDailyStore.getOrCreateEntry(on: day(10), in: context)
        JournalBlockTimelineStore.appendTextBlock(text: "Written here at ten.", createdAt: day(10), to: existing, in: context)
        try context.save()

        let drafts = [
            ImportedEntryDraft(date: day(21), text: "Imported evening.", mood: .calm, origin: "b"),
            ImportedEntryDraft(date: day(8), text: "Imported morning.", isStarred: true, origin: "a"),
            ImportedEntryDraft(date: day(9, dayOffset: 1), text: "Next day.", origin: "c")
        ]
        let summary = try await JournalImportService.commit(preview(drafts, context: context), context: context)

        let saved = try entries(in: context)
        #expect(saved.count == 2)
        let first = try #require(saved.first)
        let texts = JournalBlockTimelineStore.blocks(for: first).filter { $0.blockKind == .text }.map(\.textValue)
        #expect(texts == ["Imported morning.", "Written here at ten.", "Imported evening."])
        #expect(first.text == "Imported morning.\n\nWritten here at ten.\n\nImported evening.")
        #expect(first.isStarred)
        #expect(first.mood == Mood.calm.rawValue)

        #expect(summary.entriesAdded == 3)
        #expect(summary.daysTouched == 2)
        #expect(summary.newDays == 1)
    }

    @Test func importingTheSameFileTwiceAddsNothing() async throws {
        let context = makeContext()
        let drafts = [
            ImportedEntryDraft(date: day(8), text: "Walked to the lake.", origin: "a"),
            ImportedEntryDraft(date: day(8), text: "Walked to the lake.", origin: "copy in the same file"),
            ImportedEntryDraft(date: day(12, dayOffset: 2), text: "Lunch with Sam.", origin: "b")
        ]

        let first = preview(drafts, context: context)
        #expect(first.newDrafts.count == 2)
        #expect(first.duplicateCount == 1)
        _ = try await JournalImportService.commit(first, context: context)

        let again = preview(drafts, context: context)
        #expect(again.newDrafts.isEmpty)
        #expect(again.duplicateCount == 3)
        let summary = try await JournalImportService.commit(again, context: context)

        #expect(summary.entriesAdded == 0)
        let blocks = try entries(in: context).flatMap { JournalBlockTimelineStore.blocks(for: $0) }.filter { $0.blockKind == .text }
        #expect(blocks.count == 2)
    }

    @Test func editedTextImportsAsANewBlock() async throws {
        let context = makeContext()
        _ = try await JournalImportService.commit(preview([ImportedEntryDraft(date: day(8), text: "Version one.", origin: "a")], context: context), context: context)

        let edited = preview([ImportedEntryDraft(date: day(8), text: "Version two.", origin: "a")], context: context)
        #expect(edited.newDrafts.count == 1)
    }

    @Test func photosStopAtFivePerDay() async throws {
        let context = makeContext()
        let entry = try DiaryEntryDailyStore.getOrCreateEntry(on: day(9), in: context)
        JournalBlockTimelineStore.appendTextBlock(text: "Already has photos.", createdAt: day(9), to: entry, in: context)
        for _ in 0..<4 {
            PhotoStorageManager.shared.addPhotoData(ImportTestFixtures.pngData, to: entry, in: context)
        }
        try context.save()

        let files = ["p1.png": ImportTestFixtures.pngData, "p2.png": ImportTestFixtures.pngData, "p3.png": ImportTestFixtures.pngData]
        let draft = ImportedEntryDraft(date: day(15), text: "Three photos from the hike.", photoPaths: ["p1.png", "p2.png", "p3.png"], origin: "hike")
        let summary = try await JournalImportService.commit(preview([draft], files: files, context: context), context: context)

        #expect(summary.photosAdded == 1)
        #expect(summary.photosOverLimit == 2)
        #expect(PhotoStorageManager.shared.attachments(for: entry).count == 5)
        let photoBlocks = JournalBlockTimelineStore.blocks(for: entry).filter { $0.blockKind == .photo }
        #expect(photoBlocks.contains { $0.blockCreatedAt == day(15) })
    }

    @Test func photoOnlyEntriesAreNotImportedTwice() async throws {
        let context = makeContext()
        let files = ["photos/a.png": ImportTestFixtures.pngData]
        let draft = ImportedEntryDraft(date: day(18), text: "", photoPaths: ["photos/a.png"], origin: "photo")

        let summary = try await JournalImportService.commit(preview([draft], files: files, context: context), context: context)
        #expect(summary.photosAdded == 1)
        #expect(preview([draft], files: files, context: context).newDrafts.isEmpty)
    }

    @Test func unreadablePhotosAreCountedNotFatal() async throws {
        let context = makeContext()
        let draft = ImportedEntryDraft(date: day(18), text: "Photo went missing.", photoPaths: ["gone.png"], origin: "x")
        let summary = try await JournalImportService.commit(preview([draft], context: context), context: context)

        #expect(summary.entriesAdded == 1)
        #expect(summary.photosUnreadable == 1)
    }

    @Test func dayOneZipImportsEndToEnd() async throws {
        let context = makeContext()
        let json = #"{"entries":[{"uuid":"A","creationDate":"2025-03-04T16:15:00Z","text":"From Day One.","starred":true,"photos":[{"md5":"m1","type":"png"}]}]}"#
        let zip = ImportTestFixtures.zip([
            .init(path: "Journal.json", data: Data(json.utf8)),
            .init(path: "photos/m1.png", data: ImportTestFixtures.pngData)
        ])
        let source = ZipImportSource(archive: try ZipArchive(data: zip))
        let parsed = try JournalImportService.parse(source, as: .dayOne)
        let preview = JournalImportService.makePreview(format: .dayOne, source: source, parsed: parsed, context: context)

        let summary = try await JournalImportService.commit(preview, context: context)

        #expect(summary.entriesAdded == 1)
        #expect(summary.photosAdded == 1)
        let entry = try #require(try entries(in: context).first)
        #expect(entry.text == "From Day One.")
        #expect(entry.isStarred)
        #expect(PhotoStorageManager.shared.attachments(for: entry).first?.mimeType == "image/jpeg")
    }
}
