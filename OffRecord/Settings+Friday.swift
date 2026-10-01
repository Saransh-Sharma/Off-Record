//
//  Settings+Friday.swift
//  OffRecord
//
//  Settings › Friday: the global Friday switch. Turning her off asks first,
//  because it deletes what she remembers and the chat.
//

import SwiftUI

struct FridaySettingsSection: View {
    static let searchKeywords = "friday ai turn off on chat memory prompts"

    @AppStorage(FridayAvailability.defaultsKey) private var isFridayEnabled = true
    @State private var isConfirmingTurnOff = false

    var body: some View {
        SettingsCard(
            title: String(localized: "Friday", comment: "Settings section for the AI companion"),
            footer: String(localized: "Friday answers questions about your entries and suggests prompts."),
            systemImage: "sparkles",
            tint: OffRecordColor.textLavender,
            fill: OffRecordColor.surfacePrimary
        ) {
            Toggle(isOn: Binding(
                get: { isFridayEnabled },
                set: { turnOn in
                    if turnOn {
                        FridayAvailability.turnOn()
                    } else {
                        isConfirmingTurnOff = true
                    }
                }
            )) {
                Text("Friday", comment: "Settings toggle that turns the AI companion on or off")
            }
            .accessibilityIdentifier("settings.friday.toggle")
        }
        .alert(String(localized: "Turn Off Friday?"), isPresented: $isConfirmingTurnOff) {
            Button(String(localized: "Turn Off", comment: "Confirms turning Friday off"), role: .destructive) {
                FridayAvailability.turnOff()
                HapticManager.shared.selectionChanged()
            }
            .accessibilityIdentifier("settings.friday.turnOffConfirm")
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("What Friday remembers and your chat with her will be deleted. Your entries stay.")
        }
    }
}
