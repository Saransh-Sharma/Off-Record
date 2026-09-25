//
//  HealthStateOfMindWriter.swift
//  OffRecord
//
//  Optional, write-only sync of mood picks to Apple Health as State of Mind
//  samples. Off by default. Only the mood (valence + label) and time are
//  written — never journal text, transcripts, or people.
//

import Foundation
import HealthKit
import os.log

private let healthLogger = Logger(subsystem: "com.singularity.offrecord", category: "HealthStateOfMind")

@MainActor
final class HealthStateOfMindWriter: ObservableObject {
    static let shared = HealthStateOfMindWriter()

    static let enabledKey = "offrecord.health.stateOfMindEnabled"
    static let offeredKey = "offrecord.health.stateOfMindOffered"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var lastError: String?

    private let store = HKHealthStore()
    private let defaults = UserDefaults.standard

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Whether the Saved card should offer Health sync (once, after the first mood pick).
    var shouldOfferAfterMoodPick: Bool {
        isAvailable && !isEnabled && !defaults.bool(forKey: Self.offeredKey)
    }

    func markOffered() {
        defaults.set(true, forKey: Self.offeredKey)
    }

    /// Turns sync on (requesting write permission) or off. Returns the resulting state.
    @discardableResult
    func setEnabled(_ enabled: Bool) async -> Bool {
        markOffered()
        guard enabled else {
            isEnabled = false
            defaults.set(false, forKey: Self.enabledKey)
            return false
        }
        guard isAvailable else {
            lastError = "Apple Health isn't available on this device."
            return false
        }
        do {
            try await store.requestAuthorization(toShare: [HKSampleType.stateOfMindType()], read: [])
            let authorized = store.authorizationStatus(for: HKSampleType.stateOfMindType()) == .sharingAuthorized
            isEnabled = authorized
            defaults.set(authorized, forKey: Self.enabledKey)
            lastError = authorized ? nil : "Allow OffRecord to write State of Mind in the Health app to turn this on."
            return authorized
        } catch {
            healthLogger.error("Health authorization failed: \(error.localizedDescription, privacy: .public)")
            lastError = "Apple Health permission couldn't be requested."
            isEnabled = false
            defaults.set(false, forKey: Self.enabledKey)
            return false
        }
    }

    /// A feeling in the moment, e.g. picked right after a voice capture.
    func recordMomentaryMood(_ mood: Mood, at date: Date) {
        write(mood, kind: .momentaryEmotion, at: date)
    }

    /// The overall mood of a journal day, e.g. set from the entry's mood dial.
    func recordDailyMood(_ mood: Mood, on date: Date) {
        write(mood, kind: .dailyMood, at: date)
    }

    private func write(_ mood: Mood, kind: HKStateOfMind.Kind, at date: Date) {
        guard isEnabled, isAvailable, let mapping = Self.mapping(for: mood) else { return }
        let sample = HKStateOfMind(
            date: min(date, Date()),
            kind: kind,
            valence: mapping.valence,
            labels: [mapping.label],
            associations: []
        )
        store.save(sample) { _, error in
            if let error {
                healthLogger.error("State of Mind save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Maps OffRecord moods onto Apple's pleasantness scale (−1…1) and closest label.
    static func mapping(for mood: Mood) -> (valence: Double, label: HKStateOfMind.Label)? {
        switch mood {
        case .none: return nil
        case .excited: return (0.8, .excited)
        case .happy: return (0.7, .happy)
        case .grateful: return (0.6, .grateful)
        case .calm: return (0.4, .calm)
        case .tired: return (-0.3, .drained)
        case .anxious: return (-0.5, .anxious)
        case .sad: return (-0.6, .sad)
        case .angry: return (-0.7, .angry)
        }
    }
}
