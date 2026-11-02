//
//  JournalSchemaIntents.swift
//  OffRecord
//
//  Intents that adopt Apple's journal assistant schemas
//  (`AssistantSchemas.JournalIntent`) so Siri and Apple Intelligence can
//  create entries and search the journal. They sit beside the older intents
//  in AppIntents.swift, which keep their parameters and phrases so saved
//  shortcuts keep working.
//
//  Adopted: `.journal.createEntry`, `.journal.createAudioEntry`, `.journal.search`,
//  and `.journal.entry` on `JournalEntryEntity` (AppIntents.swift).
//
//  The entry schema is adopted only because `.journal.createEntry` must return a
//  schema entity. Its content properties stay empty on purpose: `message` (which
//  the schema maps to the `textContent` Spotlight key) is always nil and
//  `mediaItems` is always empty, so no journal text or photo reaches Siri, Apple
//  Intelligence, or the Spotlight index. The entity carries metadata only (date,
//  mood, starred, word count, recording and photo presence); see its type comment.
//
//  Not adopted, on purpose: `.journal.updateEntry` and `.journal.deleteEntry`.
//  Editing or deleting entries by voice is destructive, and the text they would
//  hand back isn't something Siri should hold.
//
//  Every intent here requires device authentication. None returns entry text.
//

import AppIntents
import CoreData
import Foundation
import GeoToolbox
import os.log

private let schemaIntentLogger = Logger(subsystem: "com.singularity.offrecord", category: "JournalSchemaIntents")

/// Creates or adds to the day's entry from text, an optional title, and photos.
/// OffRecord keeps one entry per day, so "creating" an entry adds to that day's page.
@AppIntent(schema: .journal.createEntry)
struct CreateJournalEntryIntent: AppIntent {
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    var message: AttributedString
    var title: String?
    /// OffRecord doesn't store locations; the value is ignored.
    var location: PlaceDescriptor?
    var mediaItems: [IntentFile]
    var entryDate: Date?

    func perform() async throws -> some ReturnsValue<JournalEntryEntity> & ProvidesDialog {
        let text = JournalSchemaIntentText.entryText(title: title, message: String(message.characters))
        let photos = JournalPhotoImport.capped(mediaItems.filter { JournalPhotoImport.isImportablePhoto(type: $0.type) })
        guard !text.isEmpty || !photos.isEmpty else {
            throw $message.needsValueError("What do you want to write?")
        }

        let day = JournalSchemaIntentText.entryDay(requested: entryDate, now: Date())
        let entity: JournalEntryEntity
        do {
            entity = try await DiaryEntryIntentStore.addToEntry(text: text, photoData: photos.map(\.data), on: day)
        } catch {
            schemaIntentLogger.error("Create entry failed: \(error.localizedDescription, privacy: .public)")
            throw JournalSchemaIntentError(message: String(localized: "Couldn’t save the entry. Try again in OffRecord."))
        }

        let dialog: IntentDialog = Calendar.current.isDateInToday(day)
            ? "Added to today’s entry."
            : "Added to the entry for \(day.formatted(date: .abbreviated, time: .omitted))."
        return .result(value: entity, dialog: dialog)
    }
}

/// Opens OffRecord and starts a recording, like Record Entry.
@AppIntent(schema: .journal.createAudioEntry)
struct CreateAudioJournalEntryIntent: AppIntent {
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    func perform() async throws -> some IntentResult {
        await SystemSurfaceActions.openRecording()
        return .result()
    }
}

/// Opens Timeline with the search applied.
@AppIntent(schema: .journal.search)
struct SearchJournalEntriesIntent: ShowInAppSearchResultsIntent {
    static var searchScopes: [StringSearchScope] = [.general]
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    var criteria: StringSearchCriteria

    func perform() async throws -> some IntentResult {
        let term = criteria.term.trimmingCharacters(in: .whitespacesAndNewlines)
        OffRecordNavigationRouter.storePendingRoute(.timeline(query: term.isEmpty ? nil : term))
        return .result()
    }
}

/// Pure helpers for the schema intents, kept separate so tests can reach them.
enum JournalSchemaIntentText {
    /// The text to add: the title on its own line above the message, either one alone, or empty.
    static func entryText(title: String?, message: String) -> String {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (title.isEmpty, message.isEmpty) {
        case (false, false): return "\(title)\n\n\(message)"
        case (false, true): return title
        default: return message
        }
    }

    /// The day an entry lands on: the requested date, or now when none is given
    /// or it is in the future.
    static func entryDay(requested: Date?, now: Date) -> Date {
        guard let requested, requested <= now else { return now }
        return requested
    }
}

private struct JournalSchemaIntentError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
