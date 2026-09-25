//
//  CaptureActivityAttributes.swift
//  OffRecordSystemShared
//
//  Live Activity model for an in-progress voice capture. It carries timing
//  only: no prompt, transcript, or journal text ever reaches the Lock Screen.
//

import ActivityKit
import Foundation

struct CaptureActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the running timer started, shifted forward by any paused time.
        var startDate: Date
        var isPaused: Bool
        /// Recorded time at the moment of pausing; shown as a frozen clock.
        var pausedElapsed: TimeInterval

        func elapsed(at date: Date = Date()) -> TimeInterval {
            isPaused ? pausedElapsed : max(0, date.timeIntervalSince(startDate))
        }
    }
}
