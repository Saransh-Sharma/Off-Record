import Foundation
import Testing
import UniformTypeIdentifiers
@testable import OffRecord

/// The journal schema intents and the entity they return expose metadata only.
struct JournalSchemaIntentTests {

    @Test func entityNeverCarriesEntryTextOrPhotos() {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let metadata = JournalSpotlightMetadata(
            id: UUID(),
            date: date,
            updatedAt: nil,
            mood: Mood.calm.rawValue,
            wordCount: 120,
            isStarred: false,
            hasAudio: true,
            hasPhotos: true
        )

        let entity = JournalEntryEntity(metadata: metadata)

        #expect(entity.message == nil)
        #expect(entity.mediaItems.isEmpty)
        #expect(entity.location == nil)
        #expect(entity.entryDate == date)
        #expect(entity.title == JournalEntryEntity.displayTitle(for: date))
        #expect(entity.title?.hasPrefix("Journal Entry") == true)
    }

    @Test func entryTextPutsTheTitleAboveTheMessage() {
        #expect(JournalSchemaIntentText.entryText(title: "Saturday", message: "Long walk.") == "Saturday\n\nLong walk.")
        #expect(JournalSchemaIntentText.entryText(title: "  ", message: " Long walk. ") == "Long walk.")
        #expect(JournalSchemaIntentText.entryText(title: "Saturday", message: "") == "Saturday")
        #expect(JournalSchemaIntentText.entryText(title: nil, message: "  ").isEmpty)
    }

    @Test func entryDayNeverLandsInTheFuture() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let yesterday = now.addingTimeInterval(-86_400)

        #expect(JournalSchemaIntentText.entryDay(requested: nil, now: now) == now)
        #expect(JournalSchemaIntentText.entryDay(requested: yesterday, now: now) == yesterday)
        #expect(JournalSchemaIntentText.entryDay(requested: now.addingTimeInterval(3_600), now: now) == now)
    }

    @Test func photoImportKeepsThePickerLimit() {
        let items = Array(1...9)

        #expect(JournalPhotoImport.capped(items) == [1, 2, 3, 4, 5])
        #expect(JournalPhotoImport.capped(items, limit: 2) == [1, 2])
        #expect(JournalPhotoImport.capped(items, limit: -1).isEmpty)
        #expect(PhotoStorageManager.maximumPhotosPerImport == 5)
    }

    @Test func photoImportSkipsFilesThatArentImages() {
        #expect(JournalPhotoImport.isImportablePhoto(type: .jpeg))
        #expect(JournalPhotoImport.isImportablePhoto(type: .heic))
        #expect(JournalPhotoImport.isImportablePhoto(type: nil))
        #expect(!JournalPhotoImport.isImportablePhoto(type: .pdf))
        #expect(!JournalPhotoImport.isImportablePhoto(type: .mpeg4Audio))
    }
}

/// A picked Journaling Suggestion becomes a prompt and at most the import limit of photos.
struct JournalingSuggestionDraftTests {
    @Test func reflectionPromptWinsOverTheTitle() {
        let draft = JournalingSuggestionDraft(title: "Morning Walk", reflectionPrompts: ["  ", "What stood out today?"], photoURLs: [])
        #expect(draft.prompt == "What stood out today?")
    }

    @Test func titleIsThePromptWithoutAReflection() {
        #expect(JournalingSuggestionDraft(title: " Time with Maya ", reflectionPrompts: [], photoURLs: []).prompt == "Time with Maya")
        #expect(JournalingSuggestionDraft(title: "", reflectionPrompts: [], photoURLs: []).prompt == nil)
    }

    @Test func photosKeepThePickerLimit() {
        let urls = (1...8).map { URL(fileURLWithPath: "/tmp/photo-\($0).jpg") }
        let draft = JournalingSuggestionDraft(title: "Saturday", reflectionPrompts: [], photoURLs: urls)
        #expect(draft.photosToImport == Array(urls.prefix(5)))
    }
}
