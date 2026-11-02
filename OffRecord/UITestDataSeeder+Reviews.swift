//
//  UITestDataSeeder+Reviews.swift
//  OffRecord
//
//  Fixture data for Month in Review, Year in Review, Session Prep, and
//  Import UI tests (`-ReviewsUITest`). Dates are relative to today: eight
//  entries in last month and fourteen in last year.
//

import CoreData
import Foundation

extension UITestDataSeeder {
    /// Seeds the reviews fixture and returns true when `-ReviewsUITest` is set.
    @discardableResult
    static func seedReviewsIfNeeded(arguments: [String], context: NSManagedObjectContext) -> Bool {
        guard arguments.contains("-ReviewsUITest") else { return false }
        seedPendingRouteIfNeeded(arguments: arguments)

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set("Saransh", forKey: "authorName")
        DaypartHeroStore().reset()

        for entityName in ["DiaryEntry", "AIState"] {
            let request = NSBatchDeleteRequest(fetchRequest: NSFetchRequest<NSFetchRequestResult>(entityName: entityName))
            _ = try? context.execute(request)
        }
        context.reset()
        FridayAssistantEngine.shared.resetForUITesting()
        #if DEBUG
        PeriodReviewController.shared.resetForUITesting()
        #endif
        // Keep Today's weekly card out of the way of the cards under test.
        WeeklyReflectionController.shared.updateSettings { $0.showHomeCard = false }

        let calendar = Calendar.current
        let now = Date()
        let lastMonth = ReflectionPeriodCalendar.lastCompletedPeriod(.month, before: now, calendar: calendar)
        let monthTexts = [
            "Spent the morning in the garden with Maya. The tomatoes are finally red and the basil is tall and green. We sat on the bench after and talked about the plans for next spring.",
            "Work was busy, but the garden after dinner helped. Maya brought seedlings from her balcony for the corner bed, and we planted them before it got dark outside.",
            "Quiet day. Read on the porch and watered the garden before the rain came in from the west. Made soup and went to bed early with the window open.",
            "Long week at work. The project deadline moved again and the team meeting ran late into the evening. Walked home the long way to clear my head before dinner.",
            "Planted garlic in the garden for next year. Maya says it will be ready by July if the winter is mild. The soil was soft after the rain this week.",
            "Walked by the river after work. The garden needs weeding this weekend before the leaves start to fall. Called my brother and we talked for an hour.",
            "Harvested the last tomatoes from the garden and made sauce with Maya for the freezer and for the neighbors. The kitchen smelled like summer all evening.",
            "Cleaned up the garden beds and wrote down what to plant in spring with Maya over a long cup of tea. It felt good to close out the season properly."
        ]
        let moods = ["happy", "calm", "calm", "tired", "grateful", "happy", "happy", "calm"]
        for (index, text) in monthTexts.enumerated() {
            let day = calendar.date(byAdding: .day, value: 1 + index * 3, to: lastMonth.start) ?? lastMonth.start
            let date = calendar.date(byAdding: .hour, value: 19, to: day) ?? day
            insertReviewEntry(date: date, text: text, mood: moods[index], starred: index == 6, context: context)
        }
        if arguments.contains("-ReviewsHighRisk") {
            let day = calendar.date(byAdding: .day, value: 25, to: lastMonth.start) ?? lastMonth.start
            insertReviewEntry(date: calendar.date(byAdding: .hour, value: 21, to: day) ?? day, text: "I keep thinking about ending my life tonight.", mood: "sad", starred: false, context: context)
        }

        let lastYear = calendar.component(.year, from: now) - 1
        let yearTexts = [
            "New year walk along the lake with Maya. Cold air, bright sun, and a long talk about the garden plans for spring. We stopped for coffee on the way back and stayed until the light went orange over the water.",
            "Started a reading habit before bed. Finished the first book this month and the evenings feel slower and calmer. The phone stays in the kitchen now, and I fall asleep earlier than I have in a long time.",
            "Work got busy with the spring launch. Long days, but the team pulled together and the project shipped on time. I was proud of how calm everyone stayed when the last bug showed up the night before release.",
            "First seeds went into the garden today. Tomatoes, basil, and peppers in the raised beds by the fence. Maya lent me her old watering can and we marked every row with painted stones from the beach.",
            "A trip to the coast with Sam. Walked for hours on the beach and ate fish by the harbor in the evening. The hotel was small and quiet, and we watched the boats come in from the balcony after dinner."
        ]
        for index in 0..<14 {
            let month = index % 12 + 1
            let day = index < 12 ? 10 : 20
            guard let date = calendar.date(from: DateComponents(year: lastYear, month: month, day: day, hour: 20)) else { continue }
            insertReviewEntry(date: date, text: yearTexts[index % yearTexts.count], mood: ["calm", "happy", "tired", "grateful"][index % 4], starred: index == 3, context: context)
        }

        try? context.save()
        return true
    }

    private static func insertReviewEntry(date: Date, text: String, mood: String, starred: Bool, context: NSManagedObjectContext) {
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = date
        entry.createdAt = date
        entry.updatedAt = date
        entry.text = text
        entry.setValue(mood, forKey: "mood")
        entry.isStarred = starred
        entry.duration = 0
        JournalBlockTimelineStore.backfillBlocksIfNeeded(for: entry, in: context)
    }
}
