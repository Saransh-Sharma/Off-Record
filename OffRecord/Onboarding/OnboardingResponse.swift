//
//  OnboardingResponse.swift
//  OffRecord
//
//  What onboarding remembers between launches: the reasons picked, the first
//  entry, and each permission choice, saved to UserDefaults.
//

import Foundation

struct OnboardingResponse: Codable, Equatable {
    var painPoints: Set<OnboardingPainPoint> = []
    var firstEntryText: String = ""
    var firstEntrySkipped: Bool = false
    var faceIDChoice: PermissionChoice = .notAsked
    var microphoneChoice: PermissionChoice = .notAsked
    var speechChoice: PermissionChoice = .notAsked
    var completedAt: Date?
}

struct OnboardingStore {
    private static let responseKey = "offrecord_onboarding_response"

    func save(_ response: OnboardingResponse) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        UserDefaults.standard.set(data, forKey: Self.responseKey)
    }

    static func load() -> OnboardingResponse {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITesting"), arguments.contains("-OnboardingUITest") {
            // Each UI test starts from a clean slate instead of answers saved by an earlier run.
            return OnboardingResponse()
        }
        guard let data = UserDefaults.standard.data(forKey: responseKey),
              let response = try? JSONDecoder().decode(OnboardingResponse.self, from: data) else {
            return OnboardingResponse()
        }
        return response
    }
}

enum PermissionChoice: String, Codable, Equatable {
    case notAsked
    case granted
    case denied
    case enabled
    case skipped
    case failed
}

enum OnboardingPainPoint: String, CaseIterable, Codable, Identifiable {
    case typingSlow
    case detailsFade
    case privacyWorry
    case blankPage
    case manualMood
    case hardToSearch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .typingSlow: return String(localized: "Clear my head")
        case .detailsFade: return String(localized: "Remember my days")
        case .privacyWorry: return String(localized: "Vent")
        case .blankPage: return String(localized: "Talk things through")
        case .manualMood: return String(localized: "Track my mood")
        case .hardToSearch: return String(localized: "Spot patterns")
        }
    }


    var icon: String {
        switch self {
        case .typingSlow: return "brain.head.profile"
        case .detailsFade: return "bookmark.fill"
        case .privacyWorry: return "lock"
        case .blankPage: return "bubble.left.and.bubble.right.fill"
        case .manualMood: return "heart.text.square"
        case .hardToSearch: return "point.3.connected.trianglepath.dotted"
        }
    }
}
