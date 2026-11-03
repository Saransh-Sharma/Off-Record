//
//  OnboardingStep.swift
//  OffRecord
//
//  The onboarding pages in order, with each page's title, progress, and
//  background color.
//

import SwiftUI

// MARK: - Flow State

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case intent
    case privacy
    case lock
    case firstReflection
    case habit

    var id: Int { rawValue }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var canGoBack: Bool {
        self != .welcome
    }

    var progress: Double {
        Double(rawValue + 1) / Double(Self.allCases.count)
    }

    var progressText: String {
        String(localized: "\(rawValue + 1) of \(Self.allCases.count)", comment: "Onboarding progress, e.g. “2 of 6”")
    }

    @MainActor
    var pageTitle: String {
        switch self {
        case .welcome: return String(localized: "Your private voice journal")
        case .intent: return String(localized: "What brings you here?")
        case .privacy: return String(localized: "Stays on your \(DeviceNoun.current)")
        case .lock: return String(localized: "Lock your journal")
        case .firstReflection: return String(localized: "Say one thing about today")
        case .habit: return String(localized: "Make it a habit")
        }
    }

    var backgroundColor: Color {
        switch self {
        case .welcome:
            return OffRecordColor.moodCalm
        case .intent:
            return OffRecordColor.moodGreat
        case .privacy:
            return OffRecordColor.moodGood
        case .lock:
            return OffRecordColor.moodCalm
        case .firstReflection:
            return OffRecordColor.moodCalm
        case .habit:
            return OffRecordColor.moodTired
        }
    }
}
