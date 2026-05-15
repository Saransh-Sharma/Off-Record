import CoreData
import CoreSpotlight
import Foundation
import AppIntents
import os.log
import UniformTypeIdentifiers

private let spotlightLogger = Logger(subsystem: "com.singularity.offrecord", category: "Spotlight")

struct JournalSpotlightMetadata: Equatable, Sendable {
    let id: UUID
    let date: Date
    let updatedAt: Date?
    let mood: String?
    let wordCount: Int
    let isStarred: Bool
    let hasAudio: Bool
    let hasPhotos: Bool

    var uniqueIdentifier: String {
        JournalSpotlightIndexer.entryIdentifierPrefix + id.uuidString
    }

    var title: String {
        "Journal Entry - \(Self.shortDateFormatter.string(from: date))"
    }

    var subtitle: String {
        var parts: [String] = []
        if let moodDisplayName {
            parts.append("\(moodDisplayName) mood")
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

    var keywords: [String] {
        var values: Set<String> = [
            "journal",
            "diary",
            "entry",
            "offrecord",
            Self.monthFormatter.string(from: date).lowercased(),
            Self.weekdayFormatter.string(from: date).lowercased()
        ]

        if let mood {
            values.insert(mood)
            if let moodDisplayName {
                values.insert(moodDisplayName.lowercased())
            }
        }
        if isStarred {
            values.formUnion(["starred", "favorite", "important"])
        }
        if hasAudio {
            values.formUnion(["voice", "audio", "recording"])
        }
        if hasPhotos {
            values.formUnion(["photo", "photos", "image"])
        }
        if wordCount > 0 {
            values.insert("written")
            values.insert(wordCount < 50 ? "short entry" : "long entry")
        }

        return Array(values).sorted()
    }

    private var moodDisplayName: String? {
        guard let mood, let value = Mood(rawValue: mood), value != .none else { return nil }
        return value.displayName
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}

enum JournalSpotlightMetadataBuilder {
    static func metadata(for entry: DiaryEntry) -> JournalSpotlightMetadata? {
        guard entry.isStartedEntry, let id = entry.id else { return nil }
        let audioFileName = (entry.value(forKey: "audioFileName") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return JournalSpotlightMetadata(
            id: id,
            date: entry.date ?? entry.createdAt ?? Date(),
            updatedAt: entry.updatedAt,
            mood: (entry.value(forKey: "mood") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            wordCount: entry.startedEntryWordCount,
            isStarred: entry.isStarred,
            hasAudio: !audioFileName.isEmpty || entry.duration > 0,
            hasPhotos: entry.photos?.count ?? 0 > 0
        )
    }
}

final class JournalSpotlightIndexer {
    static let shared = JournalSpotlightIndexer()

    static let entryIdentifierPrefix = "entry:"
    static let journalEntriesDomainIdentifier = "journalEntries"
    static let viewEntryActivityType = "com.singularity.offrecord.viewEntry"
    static let isEnabledDefaultsKey = "spotlightMetadataIndexingEnabled"

    private init() {}

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.isEnabledDefaultsKey) as? Bool ?? true
    }

    func upsert(entry: DiaryEntry) {
        guard isEnabled else { return }
        guard let metadata = JournalSpotlightMetadataBuilder.metadata(for: entry) else {
            if let id = entry.id {
                delete(entryID: id)
            }
            return
        }
        index(metadata: metadata)
    }

    func rebuild(entries: [DiaryEntry]) {
        guard isEnabled else {
            deleteAll()
            return
        }

        let items = entries.compactMap { entry -> CSSearchableItem? in
            guard let metadata = JournalSpotlightMetadataBuilder.metadata(for: entry) else { return nil }
            return searchableItem(for: metadata)
        }

        guard !items.isEmpty else {
            deleteAll()
            return
        }

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                spotlightLogger.error("Failed to rebuild Spotlight index: \(error.localizedDescription, privacy: .public)")
            } else {
                spotlightLogger.info("Rebuilt Spotlight metadata for \(items.count, privacy: .public) entries.")
            }
        }
    }

    func delete(entryID: UUID?) {
        guard let entryID else { return }
        let identifier = Self.entryIdentifierPrefix + entryID.uuidString
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [identifier]) { error in
            if let error {
                spotlightLogger.error("Failed to delete Spotlight item \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        NSUserActivity.deleteSavedUserActivities(withPersistentIdentifiers: [identifier]) {}
    }

    func deleteAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Self.journalEntriesDomainIdentifier]) { error in
            if let error {
                spotlightLogger.error("Failed to delete Spotlight domain: \(error.localizedDescription, privacy: .public)")
            }
        }
        NSUserActivity.deleteAllSavedUserActivities {}
    }

    func activity(for entry: DiaryEntry) -> NSUserActivity? {
        guard let metadata = JournalSpotlightMetadataBuilder.metadata(for: entry) else { return nil }

        let activity = NSUserActivity(activityType: Self.viewEntryActivityType)
        activity.title = metadata.title
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.isEligibleForHandoff = false
        activity.isEligibleForPublicIndexing = false
        activity.persistentIdentifier = metadata.uniqueIdentifier
        activity.targetContentIdentifier = metadata.uniqueIdentifier
        if #available(iOS 18.2, *) {
            activity.appEntityIdentifier = EntityIdentifier(for: JournalEntryEntity(metadata: metadata))
        }
        activity.contentAttributeSet = attributeSet(for: metadata)
        activity.userInfo = [
            CSSearchableItemActivityIdentifier: metadata.uniqueIdentifier
        ]
        return activity
    }

    func predictionActivity(type: String, title: String, route: OffRecordRoute) -> NSUserActivity? {
        guard let url = OffRecordNavigationRouter.url(for: route) else { return nil }
        let activity = NSUserActivity(activityType: type)
        activity.title = title
        activity.isEligibleForSearch = false
        activity.isEligibleForPrediction = true
        activity.isEligibleForHandoff = false
        activity.isEligibleForPublicIndexing = false
        activity.userInfo = ["offrecordRouteURL": url.absoluteString]
        return activity
    }

    private func index(metadata: JournalSpotlightMetadata) {
        CSSearchableIndex.default().indexSearchableItems([searchableItem(for: metadata)]) { error in
            if let error {
                spotlightLogger.error("Failed to index Spotlight item \(metadata.uniqueIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func searchableItem(for metadata: JournalSpotlightMetadata) -> CSSearchableItem {
        let item = CSSearchableItem(
            uniqueIdentifier: metadata.uniqueIdentifier,
            domainIdentifier: Self.journalEntriesDomainIdentifier,
            attributeSet: attributeSet(for: metadata)
        )
        item.expirationDate = Calendar.current.date(byAdding: .year, value: 2, to: Date())
        return item
    }

    private func attributeSet(for metadata: JournalSpotlightMetadata) -> CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = metadata.title
        attributes.displayName = metadata.title
        attributes.contentDescription = metadata.subtitle
        attributes.keywords = metadata.keywords
        attributes.contentCreationDate = metadata.date
        attributes.contentModificationDate = metadata.updatedAt ?? metadata.date
        return attributes
    }
}
