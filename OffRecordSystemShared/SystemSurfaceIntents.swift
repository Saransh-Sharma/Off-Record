//
//  SystemSurfaceIntents.swift
//  OffRecordSystemShared
//
//  App Intents used by widgets, controls, and the capture Live Activity.
//  This file compiles into both the app and the widget extension so the
//  system can resolve the same intent types in either process. The work
//  itself only happens in the app (`SystemSurfaceActions`); the extension
//  build compiles the declarations without the app-only calls.
//

import AppIntents
import Foundation

@available(iOS 17.0, *)
enum JournalMoodIntentValue: String, AppEnum {
    case happy
    case calm
    case grateful
    case excited
    case tired
    case anxious
    case sad
    case angry

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Mood"
    static var caseDisplayRepresentations: [JournalMoodIntentValue: DisplayRepresentation] = [
        .happy: "Happy",
        .calm: "Calm",
        .grateful: "Grateful",
        .excited: "Excited",
        .tired: "Tired",
        .anxious: "Anxious",
        .sad: "Sad",
        .angry: "Angry"
    ]
}

/// Opens OffRecord and starts a voice capture on whichever tab is showing.
/// Used by Siri, App Shortcuts, the Quick Record widget, and the Control Center control.
@available(iOS 17.0, *)
struct RecordJournalIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Journal"
    static var description = IntentDescription("Opens OffRecord to record a private voice journal entry.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if !OFFRECORD_WIDGET_EXTENSION
        await SystemSurfaceActions.openRecording()
        #endif
        return .result(dialog: "Opening OffRecord to record.")
    }
}

/// Saves a mood on today's entry from the interactive Mood widget.
/// Conforming to `LiveActivityIntent` makes the system run `perform()` in the
/// app's process, where the journal store lives, without bringing the app forward.
@available(iOS 17.0, *)
struct LogMoodIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log Mood"
    static var description = IntentDescription("Saves a mood on today's private journal entry.")
    static var isDiscoverable: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Mood")
    var mood: JournalMoodIntentValue

    init() {}

    init(mood: JournalMoodIntentValue) {
        self.mood = mood
    }

    func perform() async throws -> some IntentResult {
        #if !OFFRECORD_WIDGET_EXTENSION
        try await SystemSurfaceActions.logMood(rawValue: mood.rawValue)
        #endif
        return .result()
    }
}

/// Stops the current capture and saves it. Shown on the capture Live Activity.
@available(iOS 17.0, *)
struct StopCaptureIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Recording"
    static var description = IntentDescription("Stops the current OffRecord recording and saves it privately.")
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        #if !OFFRECORD_WIDGET_EXTENSION
        await SystemSurfaceActions.finishCapture()
        #endif
        return .result()
    }
}

/// Pauses or resumes the current capture. Shown on the capture Live Activity.
@available(iOS 17.0, *)
struct ToggleCapturePauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or Resume Recording"
    static var description = IntentDescription("Pauses or resumes the current OffRecord recording.")
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        #if !OFFRECORD_WIDGET_EXTENSION
        await SystemSurfaceActions.toggleCapturePause()
        #endif
        return .result()
    }
}
