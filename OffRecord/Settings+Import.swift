//
//  Settings+Import.swift
//  OffRecord
//
//  The Import card in Settings → Data & Export: bring entries in from Day One,
//  Apple Journal, Markdown or text files, and CSV.
//

import SwiftUI

extension SettingsView {
    var importSection: some View {
        SettingsCard(
            title: String(localized: "Import", comment: "Settings section: bring entries in from other apps"),
            systemImage: "square.and.arrow.down.on.square",
            tint: OffRecordColor.textSky,
            fill: OffRecordColor.surfacePrimary
        ) {
            NavigationLink {
                JournalImportView()
            } label: {
                SettingsActionRow(
                    systemImage: "tray.and.arrow.down",
                    title: String(localized: "From Another App", comment: "Settings row that opens the importer"),
                    subtitle: String(localized: "Day One, Apple Journal, Markdown, CSV"),
                    tint: OffRecordColor.textSky
                )
            }
            .accessibilityIdentifier("settings.import.open")
        }
    }
}
