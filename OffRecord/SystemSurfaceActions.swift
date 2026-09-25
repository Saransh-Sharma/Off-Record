//
//  SystemSurfaceActions.swift
//  OffRecord
//
//  App-side work behind the intents shared with the widget extension
//  (see OffRecordSystemShared/SystemSurfaceIntents.swift).
//

import Foundation
import os.log

private let systemSurfaceLogger = Logger(subsystem: "com.singularity.offrecord", category: "SystemSurfaces")

@MainActor
enum SystemSurfaceActions {
    /// Queues the record route and nudges a running app to consume it right away.
    static func openRecording() {
        OffRecordNavigationRouter.storePendingRoute(.record)
        NotificationCenter.default.post(name: .offRecordPendingRouteStored, object: nil)
    }

    /// Saves today's mood through the same path as Siri's "Set Today's Mood",
    /// then refreshes the widget snapshot before the widget reloads.
    static func logMood(rawValue: String) async throws {
        guard let mood = Mood(rawValue: rawValue), mood != .none else { return }
        try DiaryEntryIntentStore.setTodayMood(mood)
        systemSurfaceLogger.info("Saved mood from widget")
        await WidgetSnapshotExporter.shared.exportNow()
    }

    static func finishCapture() async {
        let controller = CaptureController.shared
        guard controller.phase.isCapturing else {
            // Nothing is recording (for example after a relaunch); clear any leftover activity.
            await CaptureLiveActivityManager.shared.endOrphanedActivities()
            return
        }
        controller.finishRecording()
    }

    static func toggleCapturePause() async {
        let controller = CaptureController.shared
        guard controller.phase == .recording || controller.phase == .paused else {
            await CaptureLiveActivityManager.shared.endOrphanedActivities()
            return
        }
        controller.togglePause()
    }
}
