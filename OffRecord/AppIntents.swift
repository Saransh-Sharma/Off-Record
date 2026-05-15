import AppIntents
import CoreData
import CoreSpotlight
import Foundation

@available(iOS 17.0, *)
enum JournalMoodIntentValue: String, AppEnum {
    case happy
    case calm
    case grateful
    case excited
    case tired
    case anxious
    case sad
    case angry

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Mood"
    static var caseDisplayRepresentations: [JournalMoodIntentValue: DisplayRepresentation] = [
        .happy: "Happy",
        .calm: "Calm",
        .grateful: "Grateful",
        .excited: "Excited",
        .tired: "Tired",
        .anxious: "Anxious",
        .sad: "Sad",
        .angry: "Angry"
    ]

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

    @Property(title: "Has Voice Note")
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
        "Journal Entry - \(Self.shortDateFormatter.string(from: date))"
    }

    var subtitle: String {
        var parts: [String] = []
        if let moodName {
            parts.append("\(moodName) mood")
        }
        if wordCount > 0 {
            parts.append("\(wordCount) \(wordCount == 1 ? "word" : "words")")
        }
        if hasAudio {
            parts.append("voice note")
        }
        if hasPhotos {
            parts.append("photos")
        }
        if isStarred {
            parts.append("starred")
        }
        return parts.isEmpty ? "Private journal entry" : parts.joined(separator: ", ")
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
struct RecordJournalIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Journal"
    static var description = IntentDescription("Opens OffRecord to record a private voice journal entry.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        OffRecordNavigationRouter.storePendingRoute(.record)
        return .result(dialog: "Opening OffRecord to record.")
    }
}

@available(iOS 17.0, *)
struct WriteJournalEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Write Journal Entry"
    static var description = IntentDescription("Adds private text to today's OffRecord journal entry.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Text", requestValueDialog: "What would you like to add to your journal?")
    var text: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Write \(\.$text) in my journal")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            throw $text.needsValueError("What would you like to add to your journal?")
        }

        await DiaryEntryIntentStore.appendToToday(text: trimmed)
        return .result(dialog: "Added to today's private journal entry.")
    }
}

@available(iOS 17.0, *)
struct OpenTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Today"
    static var description = IntentDescription("Opens today's private journal surface in OffRecord.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        OffRecordNavigationRouter.storePendingRoute(.today)
        return .result(dialog: "Opening Today in OffRecord.")
    }
}

@available(iOS 17.0, *)
struct SearchJournalIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Journal"
    static var description = IntentDescription("Opens OffRecord timeline search inside the private app.")
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
        return .result(dialog: "Opening private journal search.")
    }
}

@available(iOS 17.0, *)
struct OpenJournalEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Journal Entry"
    static var description = IntentDescription("Opens a selected private journal entry in OffRecord.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Entry")
    var entry: JournalEntryEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$entry)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        OffRecordNavigationRouter.storePendingRoute(.entry(entry.id))
        return .result(dialog: "Opening the selected journal entry.")
    }
}

@available(iOS 17.0, *)
struct SetTodayMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Today's Mood"
    static var description = IntentDescription("Sets the mood on today's private OffRecord journal entry.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Mood", requestValueDialog: "Which mood should OffRecord save for today?")
    var mood: JournalMoodIntentValue

    static var parameterSummary: some ParameterSummary {
        Summary("Set today's mood to \(\.$mood)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DiaryEntryIntentStore.setTodayMood(mood.mood)
        return .result(dialog: "Saved today's mood in OffRecord.")
    }
}

@available(iOS 17.0, *)
struct StarJournalEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Star Journal Entry"
    static var description = IntentDescription("Marks a private journal entry as starred or unstarred.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Entry")
    var entry: JournalEntryEntity

    @Parameter(title: "State")
    var state: JournalStarState

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$entry) to \(\.$state)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DiaryEntryIntentStore.setStarred(entryID: entry.id, isStarred: state.boolValue)
        return .result(dialog: state == .starred ? "Entry starred." : "Entry unstarred.")
    }
}

@available(iOS 17.0, *)
struct OpenFridayIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Friday"
    static var description = IntentDescription("Opens OffRecord's private on-device reflection assistant.")
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
    static var description = IntentDescription("Opens Friday with a private question about your journal.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Question", requestValueDialog: "What would you like to ask Friday?")
    var question: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Friday \(\.$question)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = question?.trimmingCharacters(in: .whitespacesAndNewlines)
        OffRecordNavigationRouter.storePendingRoute(.friday(question: trimmed?.isEmpty == false ? trimmed : nil))
        return .result(dialog: "Opening Friday privately.")
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
                "Record journal in \(.applicationName)",
                "Start recording in \(.applicationName)",
                "Add a voice note in \(.applicationName)"
            ],
            shortTitle: "Record",
            systemImageName: "mic.fill"
        )

        AppShortcut(
            intent: WriteJournalEntryIntent(),
            phrases: [
                "Write in \(.applicationName)",
                "Add to my journal in \(.applicationName)",
                "Save a thought in \(.applicationName)"
            ],
            shortTitle: "Write",
            systemImageName: "square.and.pencil"
        )

        AppShortcut(
            intent: SearchJournalIntent(),
            phrases: [
                "Search my journal in \(.applicationName)",
                "Find an entry in \(.applicationName)",
                "Look up my diary in \(.applicationName)"
            ],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )

        AppShortcut(
            intent: SetTodayMoodIntent(),
            phrases: [
                "Set my mood in \(.applicationName)",
                "Log my mood in \(.applicationName)",
                "Save today's mood in \(.applicationName)"
            ],
            shortTitle: "Mood",
            systemImageName: "face.smiling.fill"
        )

        AppShortcut(
            intent: AskFridayIntent(),
            phrases: [
                "Ask Friday in \(.applicationName)",
                "Talk to Friday in \(.applicationName)",
                "Ask my journal assistant in \(.applicationName)"
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

        return suggestedEntities().filter { entity in
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
    static func appendToToday(text: String) {
        let context = PersistenceController.shared.container.viewContext
        let entry = todayEntry(in: context)
        let existingText = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        entry.text = existingText.isEmpty ? text : existingText + "\n\n" + text
        entry.updatedAt = Date()
        save(context)
        EntryLearningPipeline.upsertSemanticEntry(entry)
        JournalSpotlightIndexer.shared.upsert(entry: entry)
    }

    @MainActor
    static func setTodayMood(_ mood: Mood) {
        let context = PersistenceController.shared.container.viewContext
        let entry = todayEntry(in: context)
        entry.setValue(mood.rawValue, forKey: "mood")
        entry.updatedAt = Date()
        save(context)
        EntryLearningPipeline.upsertSemanticEntry(entry)
        JournalSpotlightIndexer.shared.upsert(entry: entry)
    }

    @MainActor
    static func setStarred(entryID: UUID, isStarred: Bool) {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
        request.fetchLimit = 1
        guard let entry = try? context.fetch(request).first else { return }
        entry.isStarred = isStarred
        entry.updatedAt = Date()
        save(context)
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
    private static func todayEntry(in context: NSManagedObjectContext) -> DiaryEntry {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now

        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DiaryEntry.updatedAt, ascending: false)]
        request.fetchLimit = 1

        if let existing = try? context.fetch(request).first {
            return existing
        }

        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = now
        entry.createdAt = now
        entry.updatedAt = now
        entry.text = ""
        entry.isStarred = false
        return entry
    }

    @MainActor
    private static func fetch(_ request: NSFetchRequest<DiaryEntry>) -> [DiaryEntry] {
        (try? PersistenceController.shared.container.viewContext.fetch(request)) ?? []
    }

    @MainActor
    private static func save(_ context: NSManagedObjectContext) {
        do {
            try context.save()
        } catch {
            context.rollback()
        }
    }
}
