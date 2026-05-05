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
