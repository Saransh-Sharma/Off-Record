//
//  FridayLanguageModel.swift
//  OffRecord
//
//  One place that says whether Friday may use Apple's on-device language
//  model, and why not when she can't. Every model path (chat phrasing, Go
//  Deeper, entry titles, Weekly Reflection prose) checks this first and keeps
//  a deterministic fallback. Only `SystemLanguageModel` on this device is
//  used: no network, no Private Cloud Compute.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum FridayModelAvailability: String, Equatable, Sendable {
    case available
    /// The device can't run Apple Intelligence.
    case deviceNotEligible
    /// Apple Intelligence is turned off in Settings.
    case appleIntelligenceOff
    /// The model is still downloading or preparing.
    case notReady
    /// Turned off for UI tests and screenshots, so their copy stays fixed.
    case disabledForTesting

    var isAvailable: Bool { self == .available }

    /// Friday's one-line note for the chat, or nil when there's nothing to say.
    @MainActor var chatNote: String? {
        switch self {
        case .available, .disabledForTesting:
            return nil
        case .deviceNotEligible:
            return String(
                localized: "This \(DeviceNoun.current) can’t run Apple Intelligence, so I answer with short summaries of your entries.",
                comment: "Friday chat note. The argument is iPhone or iPad."
            )
        case .appleIntelligenceOff:
            return String(localized: "Apple Intelligence is off, so I answer with short summaries of your entries.", comment: "Friday chat note.")
        case .notReady:
            return String(localized: "Apple Intelligence is still getting ready, so I answer with short summaries for now.", comment: "Friday chat note.")
        }
    }
}

enum FridayLanguageModel {
    /// UI tests and screenshot runs keep the model off unless they opt back in,
    /// so their fixtures read the same on every Mac.
    static var isDisabledByLaunchArguments: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard !arguments.contains("-EnableOnDeviceModel") else { return false }
        return arguments.contains("-UITesting") || arguments.contains("-ScreenshotMode")
    }

    /// Lets a UI test show the unavailable state on a Mac that has the model.
    private static var forcedUnavailableReason: FridayModelAvailability? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-FridayModelUnavailable"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return FridayModelAvailability(rawValue: arguments[index + 1])
    }

    /// Whether the system model is ready on this device, ignoring test switches.
    static var systemAvailability: FridayModelAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled):
                return .appleIntelligenceOff
            case .unavailable(.modelNotReady):
                return .notReady
            case .unavailable:
                return .notReady
            }
        }
        #endif
        return .deviceNotEligible
    }

    /// What Friday may do right now.
    static var availability: FridayModelAvailability {
        if let forced = forcedUnavailableReason { return forced }
        if isDisabledByLaunchArguments { return .disabledForTesting }
        return systemAvailability
    }

    static var isAvailable: Bool { availability.isAvailable }
}
