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
        guard arguments.contains("-HeroNudgeUITest") || arguments.contains("-OnboardingUITest") || arguments.contains("-SemanticMemoryUITest") || arguments.contains("-ProactiveReflectionUITest") else { return }

        if arguments.contains("-OnboardingUITest") {
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
            UserDefaults.standard.removeObject(forKey: "authorName")
            UserDefaults.standard.removeObject(forKey: "offrecord_onboarding_response")
            DaypartHeroStore().reset()
            return
        }

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set("Saransh", forKey: "authorName")
        DaypartHeroStore().reset()

        clearEntries(in: context)
        clearAIState(in: context)

        if arguments.contains("-SemanticMemoryUITest") {
            resetSemanticMemorySidecar()
            FridayAssistantEngine.shared.resetForUITesting()
            LocalAIEngine.shared.userProfile = UserProfile()
            seedSemanticMemoryEntries(in: context)
        } else if arguments.contains("-ProactiveReflectionUITest") {
            FridayAssistantEngine.shared.resetForUITesting()
            LocalAIEngine.shared.userProfile = UserProfile()
            seedProactiveReflectionEntries(in: context)
            if arguments.contains("-ProactiveReflectionHasToday") {
                insertEntry(daysAgo: 0, text: "Today I already checked in and wrote a few grounded lines.", mood: "calm", starred: false, context: context)
            }
        } else if arguments.contains("-HeroNudgeEmptyToday") {
            insertEntry(daysAgo: 1, text: "Yesterday I noticed a few small wins worth carrying forward.", context: context)
        } else if arguments.contains("-HeroNudgeHasToday") {
            insertEntry(daysAgo: 0, text: "Today I took a quiet walk and felt more grounded afterward.", context: context)
        }

        try? context.save()
    }

    private static func clearEntries(in context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = DiaryEntry.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        _ = try? context.execute(deleteRequest)
        context.reset()
    }

    private static func clearAIState(in context: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "AIState")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        _ = try? context.execute(deleteRequest)
        context.reset()
    }

    private static func resetSemanticMemorySidecar() {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let directory = base.appendingPathComponent("OffRecordIndex", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
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

    private static func seedSemanticMemoryEntries(in context: NSManagedObjectContext) {
        let entries: [(daysAgo: Int, text: String, mood: String, starred: Bool)] = [
            (
                0,
                "After the quarterly review I felt crushed by work stress and pressure. The deadline has been stressing me lately, and Maya reminded me to take a proper lunch break.",
                "anxious",
                true
            ),
            (
                1,
                "I keep missing Mom in small moments. Her voice note from Bangalore made the apartment feel less empty, but I still wished I could sit with her over tea.",
                "sad",
                false
            ),
            (
                2,
                "I regret agreeing to the rushed project timeline. I should have pushed back earlier instead of saying yes just to keep everyone comfortable.",
                "tired",
                false
            ),
            (
                3,
                "A long run after work changed the whole evening. My body was tired, but my mind felt light and happy in a way I had not expected.",
                "happy",
                false
            ),
            (
                4,
                "Dinner with Maya and Arjun at the Bangalore cafe turned into the best conversation of the week. We talked about friendship, ambition, and rest.",
                "grateful",
                true
            ),
            (
                5,
                "The office handoff was messy again. Deadlines, Slack pings, and unclear decisions left me tense before bedtime.",
                "anxious",
                false
            ),
            (
                6,
                "I felt proud after choosing the slower but healthier option. Saying no to the extra meeting gave me space to cook and read.",
                "calm",
                false
            ),
            (
                7,
                "Spent the evening organizing old books and making tea. It was quiet, ordinary, and exactly what I needed after a noisy week.",
                "calm",
                false
            )
        ]

        for item in entries {
            insertEntry(daysAgo: item.daysAgo, text: item.text, mood: item.mood, starred: item.starred, context: context)
            FridayAssistantEngine.shared.processEntry(text: item.text, mood: item.mood, date: Date(), duration: 0)
        }
    }

    private static func seedProactiveReflectionEntries(in context: NSManagedObjectContext) {
        let entries: [(daysAgo: Int, text: String, mood: String, starred: Bool)] = [
            (1, "Yesterday I felt crushed by work pressure and stayed quiet longer than usual.", "anxious", true),
            (2, "I regret accepting the rushed project timeline. I should have pushed back before the deadline became real.", "tired", false),
            (3, "I chose the slower healthier option and skipped the extra meeting.", "calm", false),
            (4, "The deadline conversation left me tense, but a walk helped.", "anxious", false),
            (5, "Dinner with Maya helped me feel less alone after work.", "grateful", true),
            (6, "I kept thinking about the same planning mistake and wanted a better boundary.", "tired", false),
            (7, "A quiet evening made the apartment feel warm again.", "calm", false),
            (8, "Last week I felt steady after cooking and reading.", "calm", false),
            (9, "Last week work was manageable and I wrote a few notes.", "okay", false),
            (10, "Last week I was proud of saying no to one meeting.", "happy", false),
            (11, "Last week I had a good run and slept better.", "happy", false),
            (12, "Last week the project plan felt clear.", "calm", false)
        ]

        for item in entries {
            insertEntry(daysAgo: item.daysAgo, text: item.text, mood: item.mood, starred: item.starred, context: context)
            let date = Calendar.current.date(byAdding: .day, value: -item.daysAgo, to: Date()) ?? Date()
            FridayAssistantEngine.shared.processEntry(text: item.text, mood: item.mood, date: date, duration: 0)
        }
    }

    private static func insertEntry(daysAgo: Int, text: String, mood: String, starred: Bool, context: NSManagedObjectContext) {
        let calendar = Calendar.current
        let now = Date()
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = date
        entry.createdAt = date
        entry.updatedAt = date
        entry.text = text
        entry.mood = mood
        entry.isStarred = starred
        entry.duration = 0
    }
}
