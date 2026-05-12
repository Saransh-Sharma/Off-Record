import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.singularity.offrecord", category: "ReminderManager")

final class ReminderManager: ObservableObject {
    static let shared = ReminderManager()

    private let reminderEnabledKey = "solyn_reminder_enabled"
    private let reminderHourKey = "solyn_reminder_hour"
    private let reminderMinuteKey = "solyn_reminder_minute"
    private let smartPromptsKey = "offrecord_reminder_smart_prompts"
    private let notificationIdentifier = "solyn_daily_reminder"
    private let fallbackBody = "Take a minute to speak about your day."

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: reminderEnabledKey)
            if isEnabled {
                scheduleReminder()
            } else {
                cancelReminder()
            }
        }
    }

    @Published var reminderHour: Int {
        didSet {
            UserDefaults.standard.set(reminderHour, forKey: reminderHourKey)
            if isEnabled { scheduleReminder() }
        }
    }

    @Published var reminderMinute: Int {
        didSet {
            UserDefaults.standard.set(reminderMinute, forKey: reminderMinuteKey)
            if isEnabled { scheduleReminder() }
        }
    }

    @Published var usesFridaySmartPrompts: Bool {
        didSet {
            UserDefaults.standard.set(usesFridaySmartPrompts, forKey: smartPromptsKey)
            if isEnabled { reconcileScheduleIfNeeded() }
        }
    }

    var reminderTime: Date {
        get {
            var components = DateComponents()
            components.hour = reminderHour
            components.minute = reminderMinute
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = components.hour ?? 20
            reminderMinute = components.minute ?? 0
        }
    }

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: reminderEnabledKey)
        self.reminderHour = UserDefaults.standard.object(forKey: reminderHourKey) as? Int ?? 20
        self.reminderMinute = UserDefaults.standard.object(forKey: reminderMinuteKey) as? Int ?? 0
        self.usesFridaySmartPrompts = UserDefaults.standard.object(forKey: smartPromptsKey) as? Bool ?? false
    }

    func requestPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                if settings.authorizationStatus == .notDetermined {
                    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        DispatchQueue.main.async {
                            completion(granted)
                        }
                    }
                } else {
                    completion(settings.authorizationStatus == .authorized)
                }
            }
        }
    }

    func reconcileScheduleIfNeeded(now: Date = Date()) {
        guard isEnabled else {
            cancelReminder()
            return
        }
        scheduleReminder(now: now)
    }

    func reminderBody() -> String {
        usesFridaySmartPrompts
            ? ProactiveReflectionController.shared.privacySafeReminderBody()
            : fallbackBody
    }

    func nextReminderDate(after now: Date = Date(), calendar: Calendar = .current) -> Date {
        var dateComponents = DateComponents()
        dateComponents.hour = reminderHour
        dateComponents.minute = reminderMinute

        return calendar.nextDate(
            after: now,
            matching: dateComponents,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? now.addingTimeInterval(24 * 60 * 60)
    }

    func makeReminderRequest(now: Date = Date(), calendar: Calendar = .current) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "OffRecord AI Journal"
        content.body = reminderBody()
        content.sound = .default

        let trigger: UNNotificationTrigger
        if usesFridaySmartPrompts {
            let nextDate = nextReminderDate(after: now, calendar: calendar)
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            var components = DateComponents()
            components.hour = reminderHour
            components.minute = reminderMinute
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }

        return UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)
    }

    func scheduleReminder(now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])

        center.add(makeReminderRequest(now: now)) { error in
            if let error = error {
                logger.error("Failed to schedule reminder: \(error.localizedDescription)")
            }
        }
    }

    func cancelReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }
}
