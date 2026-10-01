import CoreData
import Foundation
import Testing
import UserNotifications
@testable import OffRecord

/// The global Friday switch: on by default; off deletes what she learned and
/// said, and every Friday surface stops. Each test is synchronous on the main
/// actor and restores the switch before returning, so other suites never see
/// Friday off.
@MainActor
@Suite(.serialized)
struct FridayAvailabilityTests {

    @Test func fridayIsOnByDefault() {
        let saved = UserDefaults.standard.object(forKey: FridayAvailability.defaultsKey)
        defer { UserDefaults.standard.set(saved, forKey: FridayAvailability.defaultsKey) }

        UserDefaults.standard.removeObject(forKey: FridayAvailability.defaultsKey)

        #expect(FridayAvailability.isEnabled)
    }

    @Test func turningFridayOffDeletesHerProfileChatAndMemoryEdits() throws {
        defer { UserDefaults.standard.removeObject(forKey: FridayAvailability.defaultsKey) }
        let directory = FridayLocalDirectory.url
        let chatURL = directory.appendingPathComponent("friday-conversation.json")
        let profileURL = directory.appendingPathComponent(FridayProfileStore.fileName)
        let preferencesURL = directory.appendingPathComponent("friday-memory-preferences.json")

        let scratch = FridayAssistantEngine.makeScratch()
        scratch.learn(FridayLearningInput(id: UUID(), text: "Dinner with Maya in Bangalore helped me feel grounded.", mood: "calm", date: Date(), duration: 0))
        FridayAssistantEngine.shared.adoptProfile(from: scratch)
        #expect(FridayAssistantEngine.shared.behavioralPatterns.totalEntries == 1)
        FridayChatHistoryStore.save([FridayChatMessage(text: "What did I write about Maya?", isUser: true)])
        let maya = PersonalKnowledgeGraph.KnowledgeNode(id: "maya", label: "Maya", type: .person, firstSeen: Date(), lastSeen: Date())
        FridayMemoryPreferences.shared.rename(maya, to: "M")
        #expect(FileManager.default.fileExists(atPath: profileURL.path))
        #expect(FileManager.default.fileExists(atPath: chatURL.path))
        #expect(FileManager.default.fileExists(atPath: preferencesURL.path))

        FridayAvailability.turnOff()

        #expect(!FridayAvailability.isEnabled)
        #expect(!FileManager.default.fileExists(atPath: profileURL.path))
        #expect(!FileManager.default.fileExists(atPath: chatURL.path))
        #expect(!FileManager.default.fileExists(atPath: preferencesURL.path))
        #expect(FridayAssistantEngine.shared.knowledgeGraph.nodes.isEmpty)
        #expect(FridayAssistantEngine.shared.behavioralPatterns.totalEntries == 0)
        #expect(FridayMemoryPreferences.shared.aliases.isEmpty)
        #expect(ProactiveReflectionController.shared.insights.isEmpty)
        #expect(ProactiveReflectionController.shared.selectedPrompt == nil)
    }

    @Test func proactiveCardsDoNotRefreshWhileFridayIsOff() {
        defer { UserDefaults.standard.removeObject(forKey: FridayAvailability.defaultsKey) }
        let context = PersistenceController(inMemory: true).container.viewContext
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = Date()
        entry.updatedAt = Date()
        entry.text = "Should I take the job offer in Pune?"

        UserDefaults.standard.set(false, forKey: FridayAvailability.defaultsKey)

        #expect(ProactiveReflectionController.shared.refresh(entries: [entry]) == nil)
        #expect(ProactiveReflectionController.shared.refreshIfNeeded(entries: [entry], force: true) == nil)
        #expect(ProactiveReflectionController.shared.insights.isEmpty)
    }

    @Test func fridayRouteLandsOnTheOffStateWithoutTheQuestion() {
        let router = OffRecordNavigationRouter.shared
        let savedTab = router.selectedTab
        defer {
            UserDefaults.standard.removeObject(forKey: FridayAvailability.defaultsKey)
            router.fridayQuestion = nil
            router.selectedTab = savedTab
        }

        UserDefaults.standard.set(false, forKey: FridayAvailability.defaultsKey)
        router.route(.friday(question: "How was my week?"), canNavigate: true)
        #expect(router.selectedTab == .friday)
        #expect(router.fridayQuestion == nil)

        UserDefaults.standard.set(true, forKey: FridayAvailability.defaultsKey)
        router.route(.friday(question: "How was my week?"), canNavigate: true)
        #expect(router.fridayQuestion == "How was my week?")
    }

    @Test func smartPromptsFallBackToThePlainReminderWhileFridayIsOff() {
        let manager = ReminderManager.shared
        let savedEnabled = manager.isEnabled
        let savedSmartPrompts = manager.usesFridaySmartPrompts
        defer {
            UserDefaults.standard.removeObject(forKey: FridayAvailability.defaultsKey)
            manager.usesFridaySmartPrompts = savedSmartPrompts
            manager.isEnabled = savedEnabled
        }
        manager.isEnabled = false
        manager.usesFridaySmartPrompts = true
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        UserDefaults.standard.set(false, forKey: FridayAvailability.defaultsKey)
        let off = manager.makeReminderRequest(now: now)
        #expect(off.content.title.isEmpty)
        #expect(off.content.body == String(localized: "How was today?"))
        #expect((off.trigger as? UNCalendarNotificationTrigger)?.repeats == true)

        UserDefaults.standard.set(true, forKey: FridayAvailability.defaultsKey)
        let on = manager.makeReminderRequest(now: now)
        #expect(on.content.title == String(localized: "Friday", comment: "Name of the in-app assistant, shown as the reminder notification title"))
    }
}
