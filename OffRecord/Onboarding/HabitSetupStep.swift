//
//  HabitSetupStep.swift
//  OffRecord
//
//  Onboarding step 6: an optional daily reminder and weekly goal.
//

import SwiftUI

struct HabitSetupStep: View {
    @ObservedObject var reminderManager: ReminderManager
    @ObservedObject var goalManager: GoalManager
    let onReminderDenied: () -> Void

    var body: some View {
        OnboardingQuestion(
            subtitle: String(localized: "Optional. You can change these in Settings."),
            contentSpacing: 18
        ) {
            VStack(spacing: 16) {
                Toggle(isOn: Binding(
                    get: { reminderManager.isEnabled },
                    set: { newValue in
                        if newValue {
                            reminderManager.requestPermissionIfNeeded { granted in
                                if granted {
                                    reminderManager.isEnabled = true
                                } else {
                                    reminderManager.isEnabled = false
                                    onReminderDenied()
                                }
                            }
                        } else {
                            reminderManager.isEnabled = false
                        }
                    }
                )) {
                    Label("Daily Reminder", systemImage: "bell.badge.fill")
                }
                .tint(OffRecordColor.textBrand)
                .padding()
                .background(OnboardingPalette.surfaceSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if reminderManager.isEnabled {
                    DatePicker(
                        "Time",
                        selection: Binding(
                            get: { reminderManager.reminderTime },
                            set: { reminderManager.reminderTime = $0 }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .padding()
                    .background(OnboardingPalette.surfaceSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Toggle(isOn: $goalManager.isEnabled) {
                    Label("Weekly Goal", systemImage: "flame.fill")
                }
                .tint(.orange)
                .padding()
                .background(OnboardingPalette.surfaceSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if goalManager.isEnabled {
                    Stepper(value: $goalManager.weeklyTarget, in: 1...7) {
                        Text("^[\(goalManager.weeklyTarget) day](inflect: true) a week")
                    }
                    .padding()
                    .background(OnboardingPalette.surfaceSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }
}
