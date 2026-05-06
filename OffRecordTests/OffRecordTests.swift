//
//  OffRecordTests.swift
//  OffRecordTests
//
//  Created by Karthikeyan NG on 01/12/25.
//

import Testing
import Foundation
import CryptoKit
@testable import OffRecord

// MARK: - Mood Tests

struct MoodTests {

    @Test func allMoodsHaveDisplayNames() {
        for mood in Mood.allCases {
            #expect(!mood.displayName.isEmpty, "Mood \(mood.rawValue) should have a display name")
        }
    }

    @Test func allMoodsHaveIcons() {
        for mood in Mood.allCases {
            #expect(!mood.icon.isEmpty, "Mood \(mood.rawValue) should have an icon")
        }
    }

    @Test func selectableMoodsExcludeNone() {
        let selectable = Mood.selectableMoods
        #expect(!selectable.contains(.none))
        #expect(selectable.count == Mood.allCases.count - 1)
    }

    @Test func moodInitFromRawValue() {
        #expect(Mood(rawValue: "happy") == .happy)
        #expect(Mood(rawValue: "sad") == .sad)
        #expect(Mood(rawValue: "") == Mood.none)
        #expect(Mood(rawValue: "invalid") == nil)
    }

    @Test func moodIdentifiable() {
        for mood in Mood.allCases {
            #expect(mood.id == mood.rawValue)
        }
    }
}

// MARK: - Onboarding Tests

struct OnboardingResponseTests {

    @Test func defaultResponseStartsUnanswered() {
        let response = OnboardingResponse()

        #expect(response.goal == nil)
        #expect(response.painPoints.isEmpty)
        #expect(response.relatableStatements.isEmpty)
        #expect(response.reflectionFocus == nil)
        #expect(response.promptStyle == nil)
        #expect(response.faceIDChoice == .notAsked)
        #expect(response.microphoneChoice == .notAsked)
        #expect(response.speechChoice == .notAsked)
        #expect(response.firstEntryText.isEmpty)
    }

    @Test func responseCodableRoundTrip() throws {
        var response = OnboardingResponse()
        response.goal = .fridayInsights
        response.painPoints = [.typingSlow, .privacyWorry]
        response.relatableStatements = [.honestVersion, .patternWish]
        response.reflectionFocus = .relationships
        response.promptStyle = .gentle
        response.moodBaseline = .hopeful
        response.firstEntryText = "Today I noticed I needed a private place to think."
        response.faceIDChoice = .enabled
        response.microphoneChoice = .granted
        response.speechChoice = .granted

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(OnboardingResponse.self, from: data)

        #expect(decoded == response)
    }
}

// MARK: - Encryption Tests

struct EncryptionTests {

    @Test func encryptAndDecryptRoundTrip() throws {
        let originalData = Data("Hello, OffRecord AI Journal! This is a test entry.".utf8)
        let password = "SecurePassword123!"

        let encrypted = try EncryptionService.encrypt(data: originalData, password: password)
        let decrypted = try EncryptionService.decrypt(data: encrypted, password: password)

        #expect(decrypted == originalData)
    }

    @Test func encryptionProducesDifferentOutput() throws {
        let data = Data("Test data".utf8)
        let password = "password"

        let encrypted1 = try EncryptionService.encrypt(data: data, password: password)
        let encrypted2 = try EncryptionService.encrypt(data: data, password: password)

        // Different salt each time means different ciphertext
        #expect(encrypted1 != encrypted2)
    }

    @Test func decryptWithWrongPasswordFails() throws {
        let data = Data("Secret diary entry".utf8)
        let encrypted = try EncryptionService.encrypt(data: data, password: "correct")

        #expect(throws: EncryptionService.EncryptionError.self) {
            _ = try EncryptionService.decrypt(data: encrypted, password: "wrong")
        }
    }

    @Test func encryptEmptyPasswordThrows() {
        let data = Data("test".utf8)
        #expect(throws: EncryptionService.EncryptionError.invalidPassword) {
            _ = try EncryptionService.encrypt(data: data, password: "")
        }
    }

    @Test func decryptEmptyPasswordThrows() {
        let data = Data("test".utf8)
        #expect(throws: EncryptionService.EncryptionError.invalidPassword) {
            _ = try EncryptionService.decrypt(data: data, password: "")
        }
    }

    @Test func decryptInvalidDataThrows() {
        let invalidData = Data("not encrypted".utf8)
        #expect(throws: EncryptionService.EncryptionError.invalidFileFormat) {
            _ = try EncryptionService.decrypt(data: invalidData, password: "password")
        }
    }

    @Test func encryptedDataContainsMagicBytes() throws {
        let data = Data("test".utf8)
        let encrypted = try EncryptionService.encrypt(data: data, password: "password")

        // DVX1 magic bytes
        #expect(encrypted[0] == 0x44) // D
        #expect(encrypted[1] == 0x56) // V
        #expect(encrypted[2] == 0x58) // X
        #expect(encrypted[3] == 0x31) // 1
    }

    @Test func encryptLargeData() throws {
        let largeData = Data(repeating: 0xAB, count: 1_000_000) // 1MB
        let password = "strongPassword"

        let encrypted = try EncryptionService.encrypt(data: largeData, password: password)
        let decrypted = try EncryptionService.decrypt(data: encrypted, password: password)

        #expect(decrypted == largeData)
    }
}

// MARK: - EncryptionError Tests

struct EncryptionErrorTests {

    @Test func errorDescriptionsExist() {
        let errors: [EncryptionService.EncryptionError] = [
            .invalidData, .invalidPassword, .decryptionFailed, .invalidFileFormat
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
}

// MARK: - Daypart Hero Tests

struct DaypartHeroTests {

    @Test func daypartBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        #expect(DayPart.current(for: date(hour: 4, minute: 59, calendar: calendar), calendar: calendar) == .night)
        #expect(DayPart.current(for: date(hour: 5, minute: 0, calendar: calendar), calendar: calendar) == .morning)
        #expect(DayPart.current(for: date(hour: 12, minute: 0, calendar: calendar), calendar: calendar) == .afternoon)
        #expect(DayPart.current(for: date(hour: 17, minute: 0, calendar: calendar), calendar: calendar) == .evening)
        #expect(DayPart.current(for: date(hour: 21, minute: 0, calendar: calendar), calendar: calendar) == .night)
    }

    @Test func assetPrefixMappingCoversSuppliedImages() {
        #expect(DaypartHeroLibrary.assets.count == 17)
        #expect(DaypartHeroLibrary.assets.filter { $0.dayPart == .morning }.count == 4)
        #expect(DaypartHeroLibrary.assets.filter { $0.dayPart == .afternoon }.count == 5)
        #expect(DaypartHeroLibrary.assets.filter { $0.dayPart == .evening }.count == 6)
        #expect(DaypartHeroLibrary.assets.filter { $0.dayPart == .night }.count == 2)
        #expect(DaypartHeroAsset(imageName: "morning_04_sunlit_window_coffee")?.dayPart == .morning)
        #expect(DaypartHeroAsset(imageName: "not_a_daypart") == nil)
    }

    @Test func promptFilteringUsesDaypartAndUseCase() {
        let morningEmpty = DaypartHeroLibrary.prompts(dayPart: .morning, useCase: .noEntryYet)
        let morningFull = DaypartHeroLibrary.prompts(dayPart: .morning, useCase: .hasEntryAlready)

        #expect(morningEmpty.count == 6)
        #expect(morningFull.count == 3)
        #expect(morningEmpty.allSatisfy { $0.dayPart == .morning && $0.useCase == .noEntryYet })
        #expect(morningFull.allSatisfy { $0.dayPart == .morning && $0.useCase == .hasEntryAlready })
    }

    @Test func selectionAvoidsImmediatePromptAndRecentTitleRepeat() {
        let store = makeStore()
        let first = DaypartHeroLibrary.selectHero(dayPart: .evening, hasEntryToday: false, store: store, randomIndex: { _ in 0 })
        store.recordExposure(first)

        let second = DaypartHeroLibrary.selectHero(dayPart: .evening, hasEntryToday: false, store: store, randomIndex: { _ in 0 })

        #expect(second.prompt.id != first.prompt.id)
        #expect(second.prompt.title != first.prompt.title)
    }

    @Test func twoSkipsSuppressPromptForFourteenDays() {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let skipped = DaypartHeroLibrary.prompts(dayPart: .night, useCase: .noEntryYet)[0]

        store.recordSkip(promptID: skipped.id, now: now)
        #expect(!store.isSuppressed(promptID: skipped.id, now: now))

        store.recordSkip(promptID: skipped.id, now: now.addingTimeInterval(60))
        #expect(store.isSuppressed(promptID: skipped.id, now: now.addingTimeInterval(120)))

        let selected = DaypartHeroLibrary.selectHero(dayPart: .night, hasEntryToday: false, store: store, now: now.addingTimeInterval(120), randomIndex: { _ in 0 })
        #expect(selected.prompt.id != skipped.id)
    }

    @Test func longPromptResponseIncrementsAffinityAndAffectsSelectionWeight() {
        let store = makeStore()
        let boosted = DaypartHeroLibrary.prompts(dayPart: .afternoon, useCase: .noEntryYet)[0]
        store.recordPromptResponse(promptID: boosted.id, wordCount: 41)

        #expect(store.history.affinity[boosted.id] == 1)

        let selected = DaypartHeroLibrary.selectHero(dayPart: .afternoon, hasEntryToday: false, store: store, randomIndex: { _ in 1 })
        #expect(selected.prompt.id == boosted.id)
    }

    private func makeStore() -> DaypartHeroStore {
        let suiteName = "daypart-hero-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return DaypartHeroStore(defaults: defaults, key: "history")
    }

    private func date(hour: Int, minute: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 5, day: 6, hour: hour, minute: minute))!
    }
}
