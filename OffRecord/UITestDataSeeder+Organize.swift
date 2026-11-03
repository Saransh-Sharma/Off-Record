//
//  UITestDataSeeder+Organize.swift
//  OffRecord
//
//  Fixtures for the organize UI tests (person pages, tags, and journals),
//  launched with `-UITesting -OrganizeUITest`:
//
//  - Four entries mention Maya on different days; Friday remembers her.
//  - One more entry mentions Maya but is kept out of Friday, so her page must
//    leave it out.
//  - One entry is tagged Work.
//  - `-OrganizeWithJournal` adds a Travel journal with one entry today.
//

import CoreData
import Foundation

extension UITestDataSeeder {
    static let organizeKeptOutText = "Maya and I talked about the loan, which stays private."
    static let organizeTaggedText = "Planned the quarterly launch with the team."

    /// Seeds the organize fixtures. Returns true when it handled the launch.
    static func seedOrganizeIfNeeded(arguments: [String], context: NSManagedObjectContext) -> Bool {
        guard arguments.contains("-OrganizeUITest") else { return false }
        seedPendingRouteIfNeeded(arguments: arguments)

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set("Saransh", forKey: "authorName")
        defaults.set(true, forKey: FridayAvailability.defaultsKey)
        JournalSelectionPreference.lastUsedJournalID = nil
        DaypartHeroStore().reset()
        // Today shows no contextual card that could cover the Record bar.
        WeeklyReflectionController.shared.updateSettings { $0.showHomeCard = false }

        deleteAll("DiaryEntry", in: context)
        deleteAll("Tag", in: context)
        deleteAll("Journal", in: context)
        deleteAll("AIState", in: context)

        let mayaEntries: [(daysAgo: Int, text: String, mood: Mood)] = [
            (1, "Dinner with Maya by the lake. We laughed about the old flat.", .happy),
            (9, "Maya called after work and we planned the trip.", .calm),
            (40, "Coffee with Maya before the review. I felt ready.", .happy),
            (75, "Maya helped me move the bookshelf.", .grateful)
        ]
        var inputs: [FridayLearningInput] = []
        for item in mayaEntries {
            let entry = insertOrganizeEntry(daysAgo: item.daysAgo, text: item.text, mood: item.mood, in: context)
            if let input = FridayLearningInput(entry: entry) { inputs.append(input) }
        }

        let keptOut = insertOrganizeEntry(daysAgo: 20, text: organizeKeptOutText, mood: .anxious, in: context)
        keptOut.journalAIExclusion = .excludedFromAI

        let tagged = insertOrganizeEntry(daysAgo: 3, text: organizeTaggedText, mood: .excited, in: context)
        if let work = try? TagStore(context: context).findOrMakeTag(named: "Work") {
            tagged.addToTags(work)
        }

        if arguments.contains("-OrganizeWithJournal"),
           let travel = try? JournalStore(context: context).createJournal(named: "Travel") {
            insertOrganizeEntry(daysAgo: 0, text: "Packed for Goa and checked the train times.", mood: .excited, journal: travel, in: context)
        }

        try? context.save()

        // The profile rebuilder doesn't run under UI tests, so Friday learns here, and
        // Maya is added directly so the fixture doesn't depend on the name tagger.
        let assistant = FridayAssistantEngine.shared
        assistant.resetForUITesting()
        LocalAIEngine.shared.userProfile = UserProfile()
        assistant.learn(from: inputs)
        if assistant.knowledgeGraph.nodes["maya"] == nil {
            for _ in mayaEntries {
                assistant.knowledgeGraph.addOrUpdate(id: "Maya", label: "Maya", type: .person, sentiment: 0.5)
            }
        }
        return true
    }

    @discardableResult
    private static func insertOrganizeEntry(
        daysAgo: Int,
        text: String,
        mood: Mood,
        journal: Journal? = nil,
        in context: NSManagedObjectContext
    ) -> DiaryEntry {
        let now = Date()
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = date
        entry.createdAt = date
        entry.updatedAt = date
        entry.text = text
        entry.mood = mood.rawValue
        entry.isStarred = false
        entry.journal = journal
        return entry
    }

    private static func deleteAll(_ entityName: String, in context: NSManagedObjectContext) {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        for object in (try? context.fetch(request)) ?? [] {
            context.delete(object)
        }
        try? context.save()
    }
}
