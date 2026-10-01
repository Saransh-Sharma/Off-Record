//
//  EntryAIExclusionControls.swift
//  OffRecord
//
//  "Keep Out of Friday" on an entry: two toggles in the entry's More menu and
//  a one-line note on the entry while it's kept out.
//

import CoreData
import JournalFoundation
import os.log
import SwiftUI

private let exclusionControlsLogger = Logger(subsystem: "com.singularity.offrecord", category: "EntryAIExclusion")

/// Items for the entry's More menu.
struct EntryAIExclusionMenuItems: View {
    @ObservedObject var entry: DiaryEntry
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        Toggle(isOn: keepOutOfFriday) {
            Label("Keep Out of Friday", systemImage: "eye.slash")
        }
        .accessibilityHint("Stops Friday from reading or quoting this entry.")
        .accessibilityIdentifier("entryDetail.keepOutOfFriday")

        if entry.journalAIExclusion != .included {
            Toggle(isOn: skipWeeklyReflection) {
                Label("Skip Weekly Reflection", systemImage: "calendar.badge.minus")
            }
            .accessibilityHint("Leaves this entry out of Weekly Reflection too.")
            .accessibilityIdentifier("entryDetail.skipWeeklyReflection")
        }
    }

    private var keepOutOfFriday: Binding<Bool> {
        Binding(
            get: { entry.journalAIExclusion != .included },
            set: { set($0 ? .excludedFromAI : .included) }
        )
    }

    private var skipWeeklyReflection: Binding<Bool> {
        Binding(
            get: { entry.journalAIExclusion == .excludedFromAIAndReflection },
            set: { set($0 ? .excludedFromAIAndReflection : .excludedFromAI) }
        )
    }

    private func set(_ exclusion: JournalAIExclusion) {
        do {
            try EntryAIExclusionUpdater.setExclusion(exclusion, for: entry, in: entry.managedObjectContext ?? viewContext)
            HapticManager.shared.selectionChanged()
        } catch {
            exclusionControlsLogger.error("Couldn’t save the entry’s Friday setting: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// One line on the entry while it's kept out of Friday.
struct EntryAIExclusionNote: View {
    let exclusion: JournalAIExclusion

    var body: some View {
        if exclusion != .included {
            Label {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "eye.slash")
                    .accessibilityHidden(true)
            }
            .font(OffRecordTypography.metadata)
            .foregroundStyle(OffRecordColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("entryDetail.keptOutNote")
        }
    }

    private var message: String {
        exclusion == .excludedFromAIAndReflection
            ? String(localized: "Friday and Weekly Reflection won’t use this entry.")
            : String(localized: "Friday won’t read or quote this entry.")
    }
}
