//
//  ScreenshotDataSeeder.swift
//  OffRecord
//
//  Seeds realistic diary entries for App Store screenshot generation.
//  Only activates when launched with the -ScreenshotMode argument.
//
//  Photo and audio attachments are read from the directory named by the
//  OFFRECORD_SCREENSHOT_MEDIA environment variable (AppStore/seed-media in the repo,
//  passed in by ScreenshotTests). Nothing is bundled into the app; missing files are skipped.
//

import AVFoundation
import Foundation
import CoreData

@MainActor
struct ScreenshotDataSeeder {
    static let firstEntryID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let weeklyReflectionID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private static let authorName = "Alex"
    private static let todayAudioFileName = "screenshot-today.m4a"

    private struct SeedEntry {
        let text: String
        let mood: String
        let daysAgo: Int
        let starred: Bool
        let hour: Int
        let minute: Int
        let duration: Double
        /// File in `<media>/photos/`, drawn to match the moment the entry describes.
        var photo: String? = nil
    }

    // Today's entry is a voice capture followed by two photos, a mood and a typed note.
    private static let todayTranscript = "Had a wonderful morning walk in the park today. The maples are just starting to turn and there's something magical about seeing the first signs of autumn. Stopped at my favorite coffee shop on the way back and just sat by the window for a while, watching people go by. These small moments of peace are what I treasure most."
    private static let todayNote = "Wrote out a short plan for the week before logging on: finish the Q3 roadmap draft, take a real lunch break every day, call Mom on Wednesday, and book the trail permits with James and Emma. Keeping it small on purpose. Sarah texted about a photography walk this weekend, which sounds perfect. Also printing a few of the garden photos for Mom, since she keeps asking how the sunflowers turned out. Feeling rested and clear for the first time in a while. Going to protect the first hour of every morning for walks like today's."

    private static let entries: [SeedEntry] = [
        // Recent streak (last 7 days)
        SeedEntry(
            text: "Big presentation at work went really well today. Sarah and Mike gave great feedback on the quarterly report. I've been working on this for weeks and it feels incredible to see it come together. The team seemed genuinely excited about our new direction. Celebrated with the team over lunch.",
            mood: "excited", daysAgo: 1, starred: true, hour: 13, minute: 5, duration: 90
        ),
        SeedEntry(
            text: "Spent the evening reading and journaling. There's a quiet comfort in having a routine that grounds me. Made some chamomile tea, put on soft music, and just let my thoughts flow. I've been thinking a lot about what matters most to me and how I want to spend my time.",
            mood: "calm", daysAgo: 2, starred: false, hour: 21, minute: 10, duration: 60
        ),
        SeedEntry(
            text: "Grateful for my family today. Mom called and we talked for over an hour about everything and nothing. She told me stories about when I was little that I'd never heard before. Dad chimed in from the background with his usual jokes. I need to visit them more often.",
            mood: "grateful", daysAgo: 3, starred: true, hour: 19, minute: 25, duration: 150
        ),
        SeedEntry(
            text: "Started a new workout routine at the gym. Ran 3 miles on the treadmill and did some strength training. My body is sore but my mind feels clear and energized. There's something about pushing through physical discomfort that makes everything else feel easier to handle.",
            mood: "excited", daysAgo: 4, starred: false, hour: 18, minute: 45, duration: 45
        ),
        SeedEntry(
            text: "Quiet evening at home. Cooked a big batch of pasta sauce from scratch using grandma's recipe. The whole apartment smelled amazing. Watched a documentary about ocean conservation that really made me think about the small changes I can make in my daily life.",
            mood: "calm", daysAgo: 5, starred: false, hour: 17, minute: 40, duration: 80
        ),
        SeedEntry(
            text: "Had coffee with James this morning. We talked about our plans for the fall and he mentioned a hiking trip to the mountains. I love how our friendship has grown over the years. It's rare to find someone who truly understands you without needing many words.",
            mood: "happy", daysAgo: 6, starred: false, hour: 9, minute: 30, duration: 110
        ),

        // Entries spread over the past month
        SeedEntry(
            text: "Feeling a bit overwhelmed with everything going on. Work deadlines are piling up and I haven't been sleeping well. Need to take a step back and prioritize what actually matters. Maybe I should try that meditation app Lisa recommended.",
            mood: "anxious", daysAgo: 9, starred: false, hour: 22, minute: 40, duration: 60
        ),
        SeedEntry(
            text: "Beautiful sunset tonight from the rooftop. Took some photos but they don't capture how it really looked. Orange and pink streaks across the sky, the city lights just starting to flicker on below. Moments like these remind me why I moved here.",
            mood: "grateful", daysAgo: 11, starred: true, hour: 19, minute: 50, duration: 75, photo: "rooftop-sunset"
        ),
        SeedEntry(
            text: "Had a tough conversation with my manager about the project timeline. I was nervous going in, but I'm glad I spoke up about the unrealistic expectations. She actually listened and we came up with a better plan together. Standing up for myself is getting easier.",
            mood: "calm", daysAgo: 13, starred: false, hour: 17, minute: 20, duration: 90
        ),
        SeedEntry(
            text: "Tried a new recipe for Thai green curry tonight and it turned out amazing. The secret is fresh lemongrass and a good coconut milk. Shared it with my neighbor and she loved it. Cooking for others brings me so much joy.",
            mood: "happy", daysAgo: 15, starred: false, hour: 19, minute: 30, duration: 100
        ),
        SeedEntry(
            text: "Rainy day. Stayed in and finished the book I've been reading for weeks. The ending was bittersweet but beautiful. Started sketching in my notebook afterwards, just abstract patterns. Sometimes creativity flows best when there's nothing else to do.",
            mood: "calm", daysAgo: 17, starred: false, hour: 15, minute: 10, duration: 130, photo: "rainy-reading"
        ),
        SeedEntry(
            text: "Missing home today. Saw a family at the park that reminded me of weekends with my siblings growing up. We used to spend hours playing outside until the streetlights came on. Need to plan a trip back soon.",
            mood: "sad", daysAgo: 19, starred: false, hour: 18, minute: 5, duration: 55
        ),
        SeedEntry(
            text: "Great yoga class this morning. The instructor guided us through a meditation at the end that left me feeling completely at peace. I've noticed that regular practice is making a real difference in how I handle stress throughout the day.",
            mood: "calm", daysAgo: 21, starred: false, hour: 7, minute: 45, duration: 70
        ),
        SeedEntry(
            text: "Volunteered at the community garden today. Harvested tomatoes, herbs, and the last of the sunflowers with a group of amazing people. There's something deeply satisfying about working with your hands in the soil. Met a retired teacher named Margaret who told the most wonderful stories.",
            mood: "grateful", daysAgo: 23, starred: true, hour: 16, minute: 30, duration: 180, photo: "community-garden"
        ),
        SeedEntry(
            text: "Exhausted after a long week. Barely made it through the day. Sometimes you just need to acknowledge that you're running on empty and give yourself permission to rest. Tomorrow is a new day.",
            mood: "tired", daysAgo: 25, starred: false, hour: 21, minute: 30, duration: 30
        ),
        SeedEntry(
            text: "Went to an art exhibition downtown with Emma. The modern art section was thought-provoking, especially the installation about climate change. We had great conversations about art and meaning over dinner afterwards.",
            mood: "excited", daysAgo: 27, starred: false, hour: 22, minute: 5, duration: 95
        ),
        SeedEntry(
            text: "Set some new goals for the month. I want to read two books, exercise four times a week, and spend more time on my photography hobby. Writing down goals makes them feel more real and achievable. Feeling motivated and hopeful.",
            mood: "excited", daysAgo: 28, starred: false, hour: 8, minute: 30, duration: 65
        ),
        SeedEntry(
            text: "Couldn't sleep last night. My mind kept racing about the upcoming changes at work. I know worrying doesn't help but sometimes it's hard to turn off the noise. Going to try the breathing exercises Dr. Chen suggested.",
            mood: "anxious", daysAgo: 29, starred: false, hour: 6, minute: 10, duration: 40
        ),
        SeedEntry(
            text: "Perfect day for a bike ride along the waterfront. The breeze was cool and the sun warm. Stopped at a little bookshop I'd never noticed before and found a first edition poetry collection. Life has a way of surprising you when you slow down enough to notice.",
            mood: "happy", daysAgo: 30, starred: true, hour: 17, minute: 55, duration: 140
        ),

        // Additional entries to populate Friday features (knowledge graph, predictions, personality card)
        SeedEntry(
            text: "Lunch with Sarah again today. She's been going through a rough patch at her new job and I'm glad she feels comfortable opening up to me. We talked about boundaries and how hard it is to say no. I gave her the same advice James once gave me — protect your energy first.",
            mood: "calm", daysAgo: 7, starred: false, hour: 14, minute: 20, duration: 85
        ),
        SeedEntry(
            text: "Took my camera to the botanical gardens. Golden hour photography is becoming my favorite creative outlet. Captured some incredible macro shots of dew on rose petals. Sarah texted later saying my Instagram story inspired her to start painting again.",
            mood: "happy", daysAgo: 8, starred: false, hour: 18, minute: 40, duration: 95, photo: "golden-rose"
        ),
        SeedEntry(
            text: "Work meeting ran two hours over. The product launch deadline got moved up by a week and I can feel the pressure mounting. Mike pulled me aside after and said I handled the pushback really well. Small wins matter even on hard days.",
            mood: "anxious", daysAgo: 10, starred: false, hour: 20, minute: 15, duration: 70
        ),
        SeedEntry(
            text: "Evening run along the river cleared my head. Been thinking about what Mom said last weekend — that I'm always chasing the next thing instead of appreciating where I am. She's right. Gratitude isn't passive, it takes practice. Hit a new 5K personal best though.",
            mood: "grateful", daysAgo: 12, starred: false, hour: 20, minute: 30, duration: 55
        ),
        SeedEntry(
            text: "James and I finally booked the mountain hiking trip for next month. Three days, two peaks, zero cell service. Emma wants to join too which would make it even better. I've been researching trails and gear all evening. Adventure planning is its own kind of joy.",
            mood: "excited", daysAgo: 14, starred: false, hour: 21, minute: 45, duration: 120
        ),
        SeedEntry(
            text: "Deep conversation with Lisa over video call tonight. She's starting therapy and was brave enough to share that with me. It made me reflect on my own mental health journey. Writing in this journal every day has been more therapeutic than I expected. The patterns I notice in my own words surprise me.",
            mood: "calm", daysAgo: 16, starred: false, hour: 22, minute: 10, duration: 100
        ),
        SeedEntry(
            text: "Tried a new Mediterranean cooking class downtown. Made shakshuka and fresh pita from scratch. The instructor was from Tel Aviv and told the most vivid stories about food markets there. Brought leftovers to James and he said it was the best meal he'd had all month.",
            mood: "happy", daysAgo: 18, starred: false, hour: 20, minute: 10, duration: 130
        ),
        SeedEntry(
            text: "Woke up at 5am and couldn't fall back asleep. Work deadlines keep invading my dreams. Decided to be productive about it — made a priority list and knocked out three tasks before the team was even online. Felt powerful turning anxiety into momentum.",
            mood: "anxious", daysAgo: 20, starred: false, hour: 6, minute: 20, duration: 50
        ),
        SeedEntry(
            text: "Photography walk with Emma through the old town district. She has such a different eye than me — she captures people and emotions while I gravitate toward architecture and light. We're planning a joint exhibition at the community center. The creative energy between us is electric.",
            mood: "excited", daysAgo: 22, starred: false, hour: 16, minute: 45, duration: 110
        ),
        SeedEntry(
            text: "Mom and Dad visited for the weekend. Dad helped me fix the leaky faucet he's been worried about for months. Mom reorganized my entire kitchen and cooked enough food for two weeks. The house feels warmer when they're here. Already miss them.",
            mood: "grateful", daysAgo: 24, starred: true, hour: 20, minute: 0, duration: 160
        ),
        SeedEntry(
            text: "Sarah recommended a book about stoic philosophy and I devoured half of it today. The idea that we can't control events but can control our response to them really resonates. Applied it during a frustrating work call this afternoon and it genuinely helped. Growth feels tangible right now.",
            mood: "calm", daysAgo: 26, starred: false, hour: 18, minute: 30, duration: 90
        ),
        SeedEntry(
            text: "Yoga and meditation combo this morning followed by journaling at the park. Lisa says I seem more centered lately and I think she's right. My relationship with stress is changing. I'm not running from it anymore, I'm learning to sit with it. Even my photography reflects this — more stillness, less chaos.",
            mood: "calm", daysAgo: 31, starred: false, hour: 8, minute: 50, duration: 75
        ),
        SeedEntry(
            text: "Hosted a small dinner party. Sarah, James, Emma, and Lisa all came. Made grandma's pasta recipe and the Thai curry. Everyone brought wine and stories. James gave a toast about friendship that made Emma cry. These are the people who make life rich. Grateful doesn't even begin to cover it.",
            mood: "grateful", daysAgo: 33, starred: true, hour: 21, minute: 15, duration: 170
        ),
        SeedEntry(
            text: "Work project finally launched. Three months of late nights and weekend sessions and it's live. Mike sent a company-wide email praising the team. I'm proud but also exhausted. Taking tomorrow off to recharge. Sarah says I earned it — and for once I believe her.",
            mood: "excited", daysAgo: 35, starred: true, hour: 18, minute: 20, duration: 80
        ),
        SeedEntry(
            text: "Solo hike to the waterfall trail. No music, no podcasts, just birdsong and my own thoughts. Realized I've been more present this month than any time I can remember. The combination of journaling, exercise, and intentional friendship is working. Future me will thank present me for building these habits.",
            mood: "happy", daysAgo: 37, starred: false, hour: 12, minute: 40, duration: 140, photo: "waterfall-trail"
        ),
    ]

    static func seedIfNeeded(context: NSManagedObjectContext) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-ScreenshotMode") else { return }

        let defaults = UserDefaults.standard
        // Bypass onboarding, enable goals, and keep one-off prompts and overlays out of the shots.
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set(authorName, forKey: "authorName")
        defaults.set(true, forKey: "dvx_goal_enabled")
        defaults.set(5, forKey: "dvx_goal_target")
        defaults.set(GoalManager.milestones.max() ?? 0, forKey: "dvx_last_milestone")
        defaults.set(true, forKey: HealthStateOfMindWriter.offeredKey)
        defaults.set(true, forKey: SpeechTranscriptionConsent.appleSpeechProcessingKey)
        DaypartHeroStore().reset()
        defaults.removeObject(forKey: OffRecordNavigationRouter.pendingRouteDefaultsKey)
        UITestDataSeeder.seedPendingRouteIfNeeded(arguments: arguments)

        // Clean slate for reproducible screenshots
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = DiaryEntry.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        try? context.execute(deleteRequest)
        context.reset()

        // Delete existing AI state so Friday rebuilds fresh
        let aiRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "AIState")
        let aiDelete = NSBatchDeleteRequest(fetchRequest: aiRequest)
        try? context.execute(aiDelete)
        context.reset()

        // The semantic index is rebuilt from the seeded entries.
        if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(at: base.appendingPathComponent("OffRecordIndex", isDirectory: true))
        }

        let media = ProcessInfo.processInfo.environment["OFFRECORD_SCREENSHOT_MEDIA"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let today = seedTodayEntry(media: media, context: context)

        var seeded: [(entry: SeedEntry, date: Date)] = []
        for seed in entries {
            let date = timestamp(daysAgo: seed.daysAgo, hour: seed.hour, minute: seed.minute)
            let diaryEntry = DiaryEntry(context: context)
            diaryEntry.id = UUID()
            diaryEntry.date = date
            diaryEntry.createdAt = date
            diaryEntry.updatedAt = date
            diaryEntry.text = seed.text
            diaryEntry.mood = seed.mood
            diaryEntry.isStarred = seed.starred
            diaryEntry.duration = seed.duration
            JournalBlockTimelineStore.backfillBlocksIfNeeded(for: diaryEntry, in: context)
            if let photo = seed.photo {
                attachPhoto(named: photo, from: media, to: diaryEntry, at: date.addingTimeInterval(4 * 60), in: context)
            }
            diaryEntry.updatedAt = date
            seeded.append((seed, date))
        }

        do {
            try context.save()
        } catch {
            #if DEBUG
            print("ScreenshotDataSeeder: Failed to save entries - \(error)")
            #endif
        }

        seedWeeklyReflection(context: context)

        // Build semantic memory now so Friday can answer with citations as soon as she's asked.
        let started: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        started.predicate = DiaryEntry.startedEntryPredicate
        SemanticMemoryIndexController.shared.rebuildIndex(entries: (try? context.fetch(started)) ?? [])

        // Process entries through FridayAssistantEngine so Friday tab populates
        FridayAssistantEngine.shared.processEntry(text: today.text ?? "", mood: today.mood, date: today.date ?? Date(), duration: today.duration)
        for (seed, date) in seeded {
            FridayAssistantEngine.shared.processEntry(text: seed.text, mood: seed.mood, date: date, duration: seed.duration)
        }
    }

    /// Today: a voice capture with its transcript, park and café photos, a mood, and a typed note.
    private static func seedTodayEntry(media: URL?, context: NSManagedObjectContext) -> DiaryEntry {
        let capturedAt = timestamp(daysAgo: 0, hour: 8, minute: 12)
        let entry = DiaryEntry(context: context)
        entry.id = firstEntryID
        entry.date = capturedAt
        entry.createdAt = capturedAt
        entry.text = ""
        entry.isStarred = true

        if let source = media?.appendingPathComponent("today.m4a"),
           let destination = try? AudioAttachmentStore.destinationURL(for: todayAudioFileName) {
            try? FileManager.default.removeItem(at: destination)
            if (try? FileManager.default.copyItem(at: source, to: destination)) != nil {
                let duration = (try? AVAudioPlayer(contentsOf: destination).duration) ?? 24
                let byteCount = ((try? FileManager.default.attributesOfItem(atPath: destination.path)[.size]) as? NSNumber)?.int64Value ?? -1
                let attachment = AudioAttachmentStore.attachAudio(
                    fileName: todayAudioFileName,
                    duration: duration,
                    createdAt: capturedAt,
                    sourceCaptureID: nil,
                    byteCount: byteCount,
                    codec: "aac-lc",
                    to: entry,
                    in: context
                )
                JournalBlockTimelineStore.appendAudioBlock(attachment: attachment, createdAt: capturedAt, sourceCaptureID: nil, to: entry, in: context)
                if let block = JournalBlockTimelineStore.upsertTranscriptBlock(text: todayTranscript, createdAt: capturedAt, attachment: attachment, to: entry, in: context) {
                    AudioAttachmentStore.markTranscriptionCompleted(
                        attachment,
                        engine: "speechTranscriber",
                        locale: Locale(identifier: "en_US"),
                        transcriptBlockID: block.blockID
                    )
                }
            }
        }
        if JournalBlockTimelineStore.blocks(for: entry).isEmpty {
            JournalBlockTimelineStore.appendTextBlock(text: todayTranscript, createdAt: capturedAt, to: entry, in: context)
        }

        attachPhoto(named: "autumn-park", from: media, to: entry, at: capturedAt.addingTimeInterval(2 * 60), in: context)
        attachPhoto(named: "journal-window", from: media, to: entry, at: capturedAt.addingTimeInterval(28 * 60), in: context)
        JournalBlockTimelineStore.appendMoodBlock(mood: .happy, createdAt: capturedAt.addingTimeInterval(29 * 60), to: entry, in: context)
        JournalBlockTimelineStore.appendTextBlock(text: todayNote, createdAt: timestamp(daysAgo: 0, hour: 9, minute: 5), to: entry, in: context)
        entry.updatedAt = timestamp(daysAgo: 0, hour: 9, minute: 5)
        return entry
    }

    private static func attachPhoto(named name: String, from media: URL?, to entry: DiaryEntry, at date: Date, in context: NSManagedObjectContext) {
        guard let url = media?.appendingPathComponent("photos/\(name).jpg"),
              let data = try? Data(contentsOf: url),
              let attachment = PhotoStorageManager.shared.addPhotoData(data, to: entry, in: context) else { return }
        attachment.createdAt = date
        JournalBlockTimelineStore.appendPhotoBlock(attachment: attachment, createdAt: date, to: entry, in: context)
    }

    /// Last week's reflection, under a fixed ID so the screenshot test can deep-link to it.
    private static func seedWeeklyReflection(context: NSManagedObjectContext) {
        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.predicate = DiaryEntry.startedEntryPredicate
        let snapshots = ((try? context.fetch(request)) ?? []).compactMap(WeeklyReflectionEntrySnapshot.init(entry:))
        let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let report = WeeklyReflectionGenerationService.generate(
            period: WeeklyReflectionEligibilityService.period(containing: lastWeek),
            entries: snapshots
        )
        try? WeeklyReflectionRepository(context: context).save(settings: .default, reports: [withID(weeklyReflectionID, report)])
    }

    /// `WeeklyReflectionReport.id` is immutable, so swap it through the report's Codable form.
    private static func withID(_ id: UUID, _ report: WeeklyReflectionReport) -> WeeklyReflectionReport {
        guard let data = try? JSONEncoder().encode(report),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return report }
        json["id"] = id.uuidString
        guard let patched = try? JSONSerialization.data(withJSONObject: json),
              let decoded = try? JSONDecoder().decode(WeeklyReflectionReport.self, from: patched) else { return report }
        return decoded
    }

    private static func timestamp(daysAgo: Int, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}
