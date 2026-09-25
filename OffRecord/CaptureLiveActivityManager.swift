//
//  CaptureLiveActivityManager.swift
//  OffRecord
//
//  Mirrors CaptureController's phase onto a Lock Screen / Dynamic Island
//  Live Activity. Only timing is shared with the system; prompts and
//  transcripts never leave the app.
//

import ActivityKit
import Foundation
import os.log

private let liveActivityLogger = Logger(subsystem: "com.singularity.offrecord", category: "CaptureLiveActivity")

@MainActor
final class CaptureLiveActivityManager {
    static let shared = CaptureLiveActivityManager()

    private var activity: Activity<CaptureActivityAttributes>?
    private var state: CaptureActivityAttributes.ContentState?

    private init() {}

    /// Called by CaptureController whenever its phase changes.
    func captureDidChange(from oldPhase: CapturePhase, to newPhase: CapturePhase) {
        guard oldPhase != newPhase else { return }
        switch newPhase {
        case .recording:
            if oldPhase == .paused {
                resume()
            } else {
                start()
            }
        case .paused:
            pause()
        case .idle, .saved:
            end()
        case .starting:
            break
        }
    }

    /// Ends activities that no longer track a capture, such as ones left
    /// behind by an earlier launch that ended while recording.
    func endOrphanedActivities() async {
        let currentID = activity?.id
        for stale in Activity<CaptureActivityAttributes>.activities where stale.id != currentID {
            await stale.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: - Transitions

    private func start() {
        let now = Date()
        let initial = CaptureActivityAttributes.ContentState(startDate: now, isPaused: false, pausedElapsed: 0)
        state = initial

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let leftovers = Activity<CaptureActivityAttributes>.activities
        Task {
            for stale in leftovers {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
        }
        do {
            activity = try Activity.request(
                attributes: CaptureActivityAttributes(),
                content: ActivityContent(state: initial, staleDate: nil, relevanceScore: 100),
                pushType: nil
            )
        } catch {
            liveActivityLogger.error("Capture Live Activity unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pause() {
        guard var current = state, !current.isPaused else { return }
        current.pausedElapsed = current.elapsed()
        current.isPaused = true
        publish(current)
    }

    private func resume() {
        guard var current = state, current.isPaused else {
            start()
            return
        }
        current.startDate = Date().addingTimeInterval(-current.pausedElapsed)
        current.isPaused = false
        publish(current)
    }

    private func end() {
        state = nil
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func publish(_ newState: CaptureActivityAttributes.ContentState) {
        state = newState
        guard let activity else { return }
        Task {
            await activity.update(ActivityContent(state: newState, staleDate: nil, relevanceScore: 100))
        }
    }
}
