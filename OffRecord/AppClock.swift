//
//  AppClock.swift
//  OffRecord
//
//  The app's "now" for date-sensitive surfaces that UI tests need to pin,
//  such as which week Weekly Reflection covers. Debug builds accept
//  `-UITestNow <ISO 8601 instant>` at launch (for example
//  `-UITestNow 2026-05-27T12:00:00Z`); the clock then starts at that instant
//  and keeps running. Without the argument, and in every release build,
//  `AppClock.now` is `Date()`.
//

import Foundation

enum AppClock {
    static let launchArgument = "-UITestNow"

    static var now: Date {
        guard let offset else { return Date() }
        return Date().addingTimeInterval(offset)
    }

    /// Seconds from the real launch time to the pinned instant; nil without an override.
    private static let offset: TimeInterval? = {
        #if DEBUG
        return pinnedDate(in: ProcessInfo.processInfo.arguments)?.timeIntervalSinceNow
        #else
        return nil
        #endif
    }()

    /// The instant passed after `-UITestNow`, if any.
    static func pinnedDate(in arguments: [String]) -> Date? {
        guard let index = arguments.firstIndex(of: launchArgument),
              arguments.indices.contains(index + 1) else { return nil }
        return ISO8601DateFormatter().date(from: arguments[index + 1])
    }
}
