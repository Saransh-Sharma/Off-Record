import AppIntents
import CoreData
import CoreSpotlight
import Foundation
import os.log

private let intentLogger = Logger(subsystem: "com.singularity.offrecord", category: "AppIntents")

@available(iOS 17.0, *)
private struct JournalIntentPersistenceError: LocalizedError {
    let action: String
    let message: String
    let underlyingError: Error

    /// `message` is the whole sentence Siri speaks, so it can be translated as one unit.
    init(action: String, message: String, underlyingError: Error) {
        self.action = action
        self.message = message
        self.underlyingError = underlyingError
        intentLogger.error("Intent couldn’t \(action, privacy: .public): \(underlyingError.localizedDescription, privacy: .public)")
    }

    var errorDescription: String? {
        message
    }
}

@available(iOS 17.0, *)
extension JournalMoodIntentValue {
    var mood: Mood {
        Mood(rawValue: rawValue) ?? .none
    }
}

@available(iOS 17.0, *)
enum JournalStarState: String, AppEnum {
    case starred
    case unstarred

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Star State"
    static var caseDisplayRepresentations: [JournalStarState: DisplayRepresentation] = [
        .starred: "Starred",
        .unstarred: "Unstarred"
    ]

    var boolValue: Bool { self == .starred }
}

@available(iOS 17.0, *)
struct JournalEntryEntity: AppEntity, IndexedEntity {
    var id: UUID

    @Property(title: "Date")
    var date: Date

    @Property(title: "Updated")
    var updatedAt: Date

    @Property(title: "Mood")
    var mood: String?

    @Property(title: "Word Count")
    var wordCount: Int

    @Property(title: "Starred")
    var isStarred: Bool

    @Property(title: "Has Recording")
    var hasAudio: Bool

    @Property(title: "Has Photos")
    var hasPhotos: Bool

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Journal Entry"
    static var defaultQuery = JournalEntryQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitle)",
            image: .init(systemName: isStarred ? "star.fill" : "book.pages.fill")
        )
    }

    var title: String {
        String(localized: "Journal Entry, \(Self.shortDateFormatter.string(from: date))")
    }

    var subtitle: String {
        var parts: [String] = []
        if let moodName {
            parts.append(String(localized: "\(moodName) mood", comment: "Entry subtitle part, e.g. Happy mood"))
        }
        if wordCount > 0 {
            parts.append(String(AttributedString(localized: "^[\(wordCount) word](inflect: true)").characters))
        }
        if hasAudio {
            parts.append(String(localized: "recording", comment: "Entry subtitle part: the entry has a voice recording"))
        }
        if hasPhotos {
            parts.append(String(localized: "photos", comment: "Entry subtitle part: the entry has photos"))
        }
        if isStarred {
            parts.append(String(localized: "starred", comment: "Entry subtitle part: the entry is starred"))
        }
        return parts.isEmpty ? String(localized: "Journal entry") : parts.formatted(.list(type: .and, width: .narrow))
    }

    private var moodName: String? {
        guard let mood, let value = Mood(rawValue: mood), value != .none else { return nil }
        return value.displayName
    }

    init(metadata: JournalSpotlightMetadata) {
        self.id = metadata.id
        self.date = metadata.date
        self.updatedAt = metadata.updatedAt ?? metadata.date
        self.mood = metadata.mood
        self.wordCount = metadata.wordCount
        self.isStarred = metadata.isStarred
        self.hasAudio = metadata.hasAudio
        self.hasPhotos = metadata.hasPhotos
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

@available(iOS 17.0, *)
struct JournalEntryQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [JournalEntryEntity.ID]) async throws -> [JournalEntryEntity] {
        await DiaryEntryIntentStore.entities(for: identifiers)
    }

    func suggestedEntities() async throws -> [JournalEntryEntity] {
        await DiaryEntryIntentStore.suggestedEntities()
    }

    func entities(matching string: String) async throws -> [JournalEntryEntity] {
        await DiaryEntryIntentStore.entities(matching: string)
    }
}

@available(iOS 17.0, *)
struct WriteJournalEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Write in Journal"
    static var description = IntentDescription("Adds text to today’s entry.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Text", requestValueDialog: "What do you want to add?")
    var text: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Write \(\.$text) in my journal")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            throw $text.needsValueError("What do you want to add?")
        }

        do {
            try await DiaryEntryIntentStore.appendToToday(text: trimmed)
        } catch {
            throw JournalIntentPersistenceError(action: "add to today’s entry", message: String(localized: "Couldn’t add to today’s entry. Try again in OffRecord."), underlyingError: error)
        }
        return .result(dialog: "Added to today’s entry.")
    }
}

@available(iOS 17.0, *)
struct OpenTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Today"
    static var description = IntentDescription("Opens Today.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        OffRecordNavigationRouter.storePendingRoute(.today)
        return .result(dialog: "Opening Today.")
    }
}

@available(iOS 17.0, *)
struct SearchJournalIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Journal"
    static var description = IntentDescription("Searches your journal.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Search")
    var query: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Search my journal for \(\.$query)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        OffRecordNavigationRouter.storePendingRoute(.timeline(query: trimmed?.isEmpty == false ? trimmed : nil))
        return .result(dialog: "Searching.")
    }
}

@available(iOS 17.0, *)
struct OpenJournalEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Journal Entry"
    static var description = IntentDescription("Opens an entry.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Entry")
    var entry: JournalEntryEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$entry)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        OffRecordNavigationRouter.storePendingRoute(.entry(entry.id))
        return .result(dialog: "Opening entry.")
    }
}

@available(iOS 17.0, *)
struct SetTodayMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Today’s Mood"
    static var description = IntentDescription("Sets today’s mood.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Mood", requestValueDialog: "Which mood?")
    var mood: JournalMoodIntentValue

    static var parameterSummary: some ParameterSummary {
        Summary("Set today’s mood to \(\.$mood)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try await DiaryEntryIntentStore.setTodayMood(mood.mood)
        } catch {
            throw JournalIntentPersistenceError(action: "save today’s mood", message: String(localized: "Couldn’t save today’s mood. Try again in OffRecord."), underlyingError: error)
        }
        return .result(dialog: "Mood set to \(mood.mood.displayName).")
    }
}

@available(iOS 17.0, *)
struct StarJournalEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Star Journal Entry"
    static var description = IntentDescription("Stars or unstars an entry.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Entry")
    var entry: JournalEntryEntity

    @Parameter(title: "State")
    var state: JournalStarState

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$entry) to \(\.$state)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try await DiaryEntryIntentStore.setStarred(entryID: entry.id, isStarred: state.boolValue)
        } catch {
            throw JournalIntentPersistenceError(
                action: state == .starred ? "star the entry" : "unstar the entry",
                message: state == .starred
                    ? String(localized: "Couldn’t star the entry. Try again in OffRecord.")
                    : String(localized: "Couldn’t unstar the entry. Try again in OffRecord."),
                underlyingError: error
            )
        }
        return .result(dialog: state == .starred ? "Starred." : "Unstarred.")
    }
}

@available(iOS 17.0, *)
struct OpenFridayIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Friday"
    static var description = IntentDescription("Opens Friday.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        OffRecordNavigationRouter.storePendingRoute(.friday(question: nil))
        return .result(dialog: "Opening Friday.")
    }
}

@available(iOS 17.0, *)
struct AskFridayIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Friday"
    static var description = IntentDescription("Asks Friday about your journal.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Question", requestValueDialog: "What do you want to ask?")
    var question: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Friday \(\.$question)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = question?.trimmingCharacters(in: .whitespacesAndNewlines)
        OffRecordNavigationRouter.storePendingRoute(.friday(question: trimmed?.isEmpty == false ? trimmed : nil))
        return .result(dialog: "Opening Friday.")
    }
}

@available(iOS 17.0, *)
struct OffRecordShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .purple

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordJournalIntent(),
            phrases: [
                "Record in \(.applicationName)",
                "Start recording in \(.applicationName)",
                "Record an entry in \(.applicationName)"
            ],
            shortTitle: "Record",
            systemImageName: "mic.fill"
        )

        AppShortcut(
            intent: WriteJournalEntryIntent(),
            phrases: [
                "Write in \(.applicationName)",
                "Add to my journal in \(.applicationName)"
            ],
            shortTitle: "Write",
            systemImageName: "square.and.pencil"
        )

        AppShortcut(
            intent: SearchJournalIntent(),
            phrases: [
                "Search my journal in \(.applicationName)",
                "Find an entry in \(.applicationName)"
            ],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )

        AppShortcut(
            intent: SetTodayMoodIntent(),
            phrases: [
                "Set my mood in \(.applicationName)",
                "Log my mood in \(.applicationName)"
            ],
            shortTitle: "Mood",
            systemImageName: "face.smiling.fill"
        )

        AppShortcut(
            intent: AskFridayIntent(),
            phrases: [
                "Ask Friday in \(.applicationName)",
                "Talk to Friday in \(.applicationName)"
            ],
            shortTitle: "Ask Friday",
            systemImageName: "sparkles"
        )
    }
}

@available(iOS 17.0, *)
enum DiaryEntryIntentStore {
    @MainActor
    static func entities(for identifiers: [UUID]) -> [JournalEntryEntity] {
        entries(matching: NSPredicate(format: "id IN %@", identifiers))
            .compactMap(JournalSpotlightMetadataBuilder.metadata(for:))
            .map(JournalEntryEntity.init(metadata:))
    }

    @MainActor
    static func suggestedEntities() -> [JournalEntryEntity] {
        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \DiaryEntry.isStarred, ascending: false),
            NSSortDescriptor(keyPath: \DiaryEntry.updatedAt, ascending: false)
        ]
        request.fetchLimit = 12
        return fetch(request)
            .startedEntries
            .compactMap(JournalSpotlightMetadataBuilder.metadata(for:))
            .map(JournalEntryEntity.init(metadata:))
    }

    @MainActor
    static func entities(matching string: String) -> [JournalEntryEntity] {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return suggestedEntities() }

        return allEntities().filter { entity in
            [
                entity.title,
                entity.subtitle,
                entity.mood ?? "",
                entity.isStarred ? "starred favorite" : "",
                entity.hasAudio ? "voice audio recording" : "",
                entity.hasPhotos ? "photo photos image" : ""
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(trimmed)
        }
    }

    @MainActor
    private static func allEntities() -> [JournalEntryEntity] {
        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DiaryEntry.updatedAt, ascending: false)]
        return fetch(request)
            .startedEntries
            .compactMap(JournalSpotlightMetadataBuilder.metadata(for:))
            .map(JournalEntryEntity.init(metadata:))
    }

    @MainActor
    static func appendToToday(text: String) throws {
        let context = PersistenceController.shared.container.viewContext
        let entry = try JournalBlockTimelineStore.appendTextBlock(text: text, createdAt: Date(), in: context)
        try save(context)
        EntryLearningPipeline.upsertSemanticEntry(entry)
        JournalSpotlightIndexer.shared.upsert(entry: entry)
    }

    @MainActor
    static func setTodayMood(_ mood: Mood) throws {
        let context = PersistenceController.shared.container.viewContext
        let entry = try JournalBlockTimelineStore.appendMoodBlock(mood: mood, createdAt: Date(), in: context)
        try save(context)
        EntryLearningPipeline.upsertSemanticEntry(entry)
        JournalSpotlightIndexer.shared.upsert(entry: entry)
    }

    @MainActor
    static func setStarred(entryID: UUID, isStarred: Bool) throws {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
        request.fetchLimit = 1
        guard let entry = try? context.fetch(request).first else { return }
        entry.isStarred = isStarred
        entry.updatedAt = Date()
        try save(context)
        EntryLearningPipeline.upsertSemanticEntry(entry)
        JournalSpotlightIndexer.shared.upsert(entry: entry)
    }

    @MainActor
    private static func entries(matching predicate: NSPredicate) -> [DiaryEntry] {
        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DiaryEntry.updatedAt, ascending: false)]
        return fetch(request).startedEntries
    }

    @MainActor
    private static func fetch(_ request: NSFetchRequest<DiaryEntry>) -> [DiaryEntry] {
        (try? PersistenceController.shared.container.viewContext.fetch(request)) ?? []
    }

    @MainActor
    private static func save(_ context: NSManagedObjectContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
