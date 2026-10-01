//
//  Settings+EraseAllData.swift
//  OffRecord
//
//  Settings › Erase All Data. Two alerts: the first says plainly whether the
//  erase reaches iCloud, the second confirms. See JournalEraser for what goes.
//

import CoreData
import SwiftUI

struct EraseAllDataSettingsSection: View {
    static let searchKeywords = "erase delete all data reset start over"

    @ObservedObject private var capture = CaptureController.shared
    @State private var isConfirming = false
    @State private var isConfirmingAgain = false
    @State private var isErasing = false
    @State private var showsError = false

    /// Whether the open store mirrors to iCloud right now. A sync change in
    /// Settings only applies after a relaunch, so the store is what counts.
    private var syncsWithICloud: Bool {
        PersistenceController.shared.container.persistentStoreDescriptions.contains { $0.cloudKitContainerOptions != nil }
    }

    var body: some View {
        SettingsCard(
            title: String(localized: "Erase All Data"),
            footer: String(localized: "Deletes all entries, recordings, photos, and Friday’s memory."),
            systemImage: "trash",
            tint: OffRecordColor.textCoral,
            fill: OffRecordColor.surfacePrimary
        ) {
            if isErasing {
                HStack(spacing: OffRecordSpacing.sm) {
                    ProgressView()
                    Text("Erasing…", comment: "Progress text while Erase All Data runs")
                        .font(OffRecordTypography.bodySmall)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Button(role: .destructive) {
                    isConfirming = true
                } label: {
                    Label("Erase All Data", systemImage: "trash")
                }
                .buttonStyle(SettingsSecondaryButtonStyle(tint: OffRecordColor.textCoral, fill: OffRecordColor.backgroundBlushTint))
                .disabled(capture.phase.isCapturing)
                .accessibilityIdentifier("settings.eraseAllData")
            }
        }
        .alert(String(localized: "Erase All Data?"), isPresented: $isConfirming) {
            Button(String(localized: "Continue", comment: "First step of Erase All Data"), role: .destructive) {
                // Let the first alert finish dismissing before the second appears.
                DispatchQueue.main.async { isConfirmingAgain = true }
            }
            .accessibilityIdentifier("settings.eraseAllData.continue")
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(firstMessage)
        }
        .alert(String(localized: "This Can’t Be Undone"), isPresented: $isConfirmingAgain) {
            Button(String(localized: "Erase All Data"), role: .destructive) {
                erase()
            }
            .accessibilityIdentifier("settings.eraseAllData.confirm")
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("OffRecord will start fresh.")
        }
        .alert(String(localized: "Couldn’t Erase Everything"), isPresented: $showsError) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text("Try again to erase what’s left.")
        }
    }

    private var firstMessage: String {
        syncsWithICloud
            ? String(localized: "Every entry, recording, and photo will be deleted from this \(DeviceNoun.current) and from iCloud.")
            : String(localized: "Every entry, recording, and photo on this \(DeviceNoun.current) will be deleted. Copies already in iCloud stay.")
    }

    private func erase() {
        isErasing = true
        Task { @MainActor in
            do {
                try await JournalEraser.eraseEverything()
                HapticManager.shared.selectionChanged()
            } catch {
                isErasing = false
                showsError = true
            }
        }
    }
}
