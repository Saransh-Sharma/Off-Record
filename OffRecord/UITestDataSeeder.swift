//
//  UITestDataSeeder.swift
//  OffRecord
//
//  Deterministic data states for UI tests.
//

import CoreData
import Foundation

struct UITestDataSeeder {
    static func seedIfNeeded(context: NSManagedObjectContext) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-HeroNudgeUITest") else { return }

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set("Saransh", forKey: "authorName")
        DaypartHeroStore().reset()

        clearEntries(in: context)

        if arguments.contains("-HeroNudgeEmptyToday") {
            insertEntry(daysAgo: 1, text: "Yesterday I noticed a few small wins worth carrying forward.", context: context)
        } else if arguments.contains("-HeroNudgeHasToday") {
            insertEntry(daysAgo: 0, text: "Today I took a quiet walk and felt more grounded afterward.", context: context)
        }

        try? context.save()
    }

    private static func clearEntries(in context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = DiaryEntry.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        try? context.execute(deleteRequest)
        context.reset()
    }

    private static func insertEntry(daysAgo: Int, text: String, context: NSManagedObjectContext) {
        let calendar = Calendar.current
        let now = Date()
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = date
        entry.createdAt = date
        entry.updatedAt = date
        entry.text = text
        entry.isStarred = false
        entry.duration = 0
    }
}
