//
//  FridayAvailability.swift
//  OffRecord
//
//  The global Friday switch (Settings › Friday). On by default. When off,
//  Friday reads nothing: no chat, no profile rebuilds, no proactive or
//  "From Friday" cards, no Go Deeper or entry insights, and no Smart Prompt
//  content. Turning her off deletes what she learned and said. Search by
//  meaning and Weekly Reflection (which has its own switch) are unaffected.
//

import Foundation
import SwiftUI

extension Notification.Name {
    /// Posted on the main queue after Friday is turned on or off.
    static let fridayAvailabilityDidChange = Notification.Name("offrecord.fridayAvailabilityDidChange")
}

@MainActor
enum FridayAvailability {
    nonisolated static let defaultsKey = "offrecord_friday_enabled"

    /// Views can watch the same value with `@AppStorage(FridayAvailability.defaultsKey)`.
    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    static func turnOn() {
        guard !isEnabled else { return }
        UserDefaults.standard.set(true, forKey: defaultsKey)
        // She relearns from the journal; nothing was kept while she was off.
        FridayProfileRebuilder.shared.rebuildNow()
        ReminderManager.shared.reconcileScheduleIfNeeded()
        NotificationCenter.default.post(name: .fridayAvailabilityDidChange, object: nil)
    }

    /// Turns Friday off and deletes her profile, chat, memory edits, and cards.
    static func turnOff() {
        UserDefaults.standard.set(false, forKey: defaultsKey)
        forgetEverything()
        OffRecordNavigationRouter.shared.fridayQuestion = nil
        ReminderManager.shared.reconcileScheduleIfNeeded()
        NotificationCenter.default.post(name: .fridayAvailabilityDidChange, object: nil)
    }

    /// Deletes what Friday learned and said. Also used by Erase All Data.
    static func forgetEverything() {
        FridayProfileRebuilder.shared.cancelPendingRefresh()
        FridayAssistantEngine.shared.deleteProfile()
        FridayChatHistoryStore.clear()
        FridayMemoryPreferences.shared.reset()
        ProactiveReflectionController.shared.clearDerivedState()
        FridayGeneratedTextCache.removeAll()
        EntryTitleStore.shared.didForgetTitles()
        // Every Friday file lives in FridayLocal, including caches added later.
        try? FileManager.default.removeItem(at: FridayLocalDirectory.url)
    }
}
