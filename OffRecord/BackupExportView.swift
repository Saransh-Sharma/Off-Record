//
//  BackupExportView.swift
//  OffRecord
//
//  View for exporting diary data in various formats.
//

import SwiftUI
import UniformTypeIdentifiers

struct BackupExportView: View {
    let entries: [DiaryEntry]
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .json
    @State private var includeAllEntries = true
    @State private var starredOnly = false
    @State private var startDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var encryptionPassword = ""
    @State private var confirmPassword = ""
    
    private var filteredEntryCount: Int {
        // JSON and encrypted backups are always full backups; filters apply only to readable exports.
        if selectedFormat == .json || selectedFormat == .encryptedBackup {
            return entries.count
        }
        
        var filtered = entries
        
        if !includeAllEntries {
            filtered = filtered.filter { entry in
                guard let date = entry.date else { return false }
                return date >= startDate && date <= endDate
            }
        }
        
        if starredOnly {
            filtered = filtered.filter { $0.isStarred }
        }
        
        return filtered.count
    }

    private var filtersAreDisabled: Bool {
        selectedFormat == .json || selectedFormat == .encryptedBackup
    }

    private var filterFooterText: String {
        switch selectedFormat {
        case .json:
            return "JSON backups always include all entries so they can be restored completely."
        case .encryptedBackup:
            return "Encrypted backups always include all entries and can be imported back into OffRecord."
        default:
            return "\(filteredEntryCount) entries will be exported."
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
                SettingsCard(
                    title: "Export Format",
                    subtitle: "Choose a restore-ready backup or a readable file for safekeeping.",
                    systemImage: "doc.badge.arrow.up",
                    tint: OffRecordColor.textSky,
                    fill: OffRecordColor.surfacePrimary
                ) {
                ForEach(ExportFormat.allCases.filter { $0 != .pdf }, id: \.self) { format in
                    Button {
                        selectedFormat = format
                        HapticManager.shared.selectionChanged()
                    } label: {
                        HStack(spacing: 12) {
                            SettingsRow(
                                systemImage: format.icon,
                                title: format.rawValue,
                                subtitle: format.description,
                                tint: selectedFormat == format ? OffRecordColor.textSky : OffRecordColor.textSecondary
                            )
                            Spacer()
                            
                            if selectedFormat == format {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(OffRecordColor.textBrand)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(format.rawValue)
                    .accessibilityValue(selectedFormat == format ? "Selected" : "Not selected")
                    .accessibilityHint(format.description)
                    .accessibilityAddTraits(selectedFormat == format ? [.isSelected] : [])
                }
            }
            
                SettingsCard(
                    title: "Filter",
                    subtitle: filterFooterText,
                    systemImage: "line.3.horizontal.decrease.circle",
                    tint: OffRecordColor.textAqua,
                    fill: OffRecordColor.surfaceMint
                ) {
                Toggle("Include all entries", isOn: $includeAllEntries)
                
                if !includeAllEntries {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, displayedComponents: .date)
                }
                
                Toggle("Starred entries only", isOn: $starredOnly)
            }
            .disabled(filtersAreDisabled)

            // Password fields for encrypted backup
            if selectedFormat == .encryptedBackup {
                    SettingsCard(
                        title: "Encryption Password",
                        subtitle: "Choose a strong password. You'll need it to restore this backup.",
                        footer: "There is no way to recover a forgotten password.",
                        systemImage: "lock.shield.fill",
                        tint: OffRecordColor.textSage,
                        fill: OffRecordColor.surfaceSage
                    ) {
                    SecureField("Password", text: $encryptionPassword)
                            .textFieldStyle(.roundedBorder)
                    SecureField("Confirm Password", text: $confirmPassword)
                            .textFieldStyle(.roundedBorder)

                    if !encryptionPassword.isEmpty && !confirmPassword.isEmpty && encryptionPassword != confirmPassword {
                        Text("Passwords do not match")
                            .font(OffRecordTypography.metadata)
                            .foregroundColor(OffRecordColor.textCoral)
                    }
                }
            }

                SettingsCard(
                    title: "Export Privacy",
                    subtitle: "Exports are created on this device.",
                    systemImage: "lock.fill",
                    tint: OffRecordColor.textSage,
                    fill: OffRecordColor.surfacePrimary
                ) {
                if selectedFormat == .json || selectedFormat == .encryptedBackup {
                        SettingsRow(systemImage: "arrow.triangle.2.circlepath", title: "Can be imported back into OffRecord", tint: OffRecordColor.textSage)
                }

                if selectedFormat == .encryptedBackup {
                        SettingsRow(systemImage: "lock.shield.fill", title: "AES-256 encrypted with your password", tint: OffRecordColor.textSage)
                }
                
                    SettingsRow(systemImage: "lock.fill", title: "File saved to your device only", tint: OffRecordColor.textSky)
                }
            
                Button {
                    exportData()
                } label: {
                    HStack(spacing: OffRecordSpacing.sm) {
                        if isExporting {
                            ProgressView()
                                .tint(OffRecordColor.textInverse)
                        }
                        Text(isExporting ? "Exporting..." : "Export \(filteredEntryCount) Entries")
                    }
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .disabled(isExporting || filteredEntryCount == 0 || (selectedFormat == .encryptedBackup && (encryptionPassword.isEmpty || encryptionPassword != confirmPassword)))
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, OffRecordSpacing.screenX)
            .padding(.vertical, OffRecordSpacing.screenY)
        }
        .background(OffRecordColor.appBackgroundGradient)
        .navigationTitle("Export Data")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Export Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(item: Binding(
            get: { exportURL.map { IdentifiableURL(url: $0) } },
            set: { if $0 == nil { exportURL = nil } }
        )) { item in
            ShareSheet(activityItems: [item.url])
        }
    }
    
    private func exportData() {
        isExporting = true
        HapticManager.shared.buttonTap()

        let selectedFormat = selectedFormat
        let encryptionPassword = encryptionPassword
        let includeAllEntries = includeAllEntries
        let startDate = startDate
        let endDate = endDate
        let starredOnly = starredOnly
        let deviceName = BackupData.currentDeviceName()
        let exportableEntries = entries.map { ExportableEntry(from: $0) }

        Task.detached(priority: .userInitiated) {
            do {
                let url: URL
                
                switch selectedFormat {
                case .json:
                    url = try BackupService.writeJSONBackup(entries: exportableEntries, deviceName: deviceName)
                case .encryptedBackup:
                    url = try BackupService.writeEncryptedBackup(entries: exportableEntries, password: encryptionPassword, deviceName: deviceName)
                case .text, .markdown, .csv:
                    var filteredEntries = exportableEntries
                    
                    if !includeAllEntries {
                        filteredEntries = filteredEntries.filter { entry in
                            entry.date >= startDate && entry.date <= endDate
                        }
                    }
                    
                    if starredOnly {
                        filteredEntries = filteredEntries.filter { $0.isStarred }
                    }
                    
                    switch selectedFormat {
                    case .text:
                        url = try BackupService.writeTextExport(entries: filteredEntries)
                    case .markdown:
                        url = try BackupService.writeMarkdownExport(entries: filteredEntries)
                    case .csv:
                        url = try BackupService.writeCSVExport(entries: filteredEntries)
                    default:
                        // Should not be reached
                        return
                    }
                case .pdf:
                    // PDF handled separately elsewhere
                    return
                }

                await MainActor.run {
                    isExporting = false
                    exportURL = url
                    HapticManager.shared.entrySaved()
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    errorMessage = error.localizedDescription
                    showError = true
                    HapticManager.shared.error()
                }
            }
        }
    }
}

// MARK: - Import Backup View

struct ImportBackupView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var showFilePicker = false
    @State private var isImporting = false
    @State private var importResult: ImportResult?
    @State private var showResult = false
    @State private var pendingEncryptedURL: URL?
    @State private var showPasswordPrompt = false
    @State private var importPassword = ""

    enum ImportResult {
        case success(Int)
        case error(String)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
                SettingsCard(
                    title: "Import Backup",
                    subtitle: "Restore entries from a JSON backup or encrypted .dvx backup exported from OffRecord.",
                    systemImage: "doc.badge.plus",
                    tint: OffRecordColor.textSky,
                    fill: OffRecordColor.surfaceBlue
                ) {
                    Text("Select a backup file. OffRecord will skip duplicates and preserve existing entries.")
                        .font(OffRecordTypography.bodySmall)
                        .foregroundColor(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsCard(
                    title: "How it works",
                    subtitle: "Imports are additive and stay under your control.",
                    systemImage: "checkmark.seal",
                    tint: OffRecordColor.textSage,
                    fill: OffRecordColor.surfacePrimary
                ) {
                    SettingsRow(systemImage: "checkmark.circle.fill", title: "Duplicate entries are automatically skipped", tint: OffRecordColor.textSage)
                    SettingsRow(systemImage: "arrow.triangle.merge", title: "Existing entries are preserved", tint: OffRecordColor.textSky)
                    SettingsRow(systemImage: "icloud.and.arrow.up", title: "Imported entries sync to iCloud when sync is enabled", tint: OffRecordColor.textLavender)
                }

                Button {
                    showFilePicker = true
                    HapticManager.shared.buttonTap()
                } label: {
                    HStack(spacing: OffRecordSpacing.sm) {
                        if isImporting {
                            ProgressView()
                                .tint(OffRecordColor.textInverse)
                        }
                        Text(isImporting ? "Importing..." : "Select Backup File")
                    }
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .disabled(isImporting)
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, OffRecordSpacing.screenX)
            .padding(.vertical, OffRecordSpacing.screenY)
        }
        .background(OffRecordColor.appBackgroundGradient)
        .navigationTitle("Import Backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType.json, UTType(filenameExtension: "dvx") ?? UTType.data],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .sheet(isPresented: $showPasswordPrompt) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
                        SettingsCard(
                            title: "Encrypted Backup",
                            subtitle: "Enter the password used when this encrypted backup was created.",
                            systemImage: "lock.shield.fill",
                            tint: OffRecordColor.textSage,
                            fill: OffRecordColor.surfaceSage
                        ) {
                        SecureField("Password", text: $importPassword)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button {
                            showPasswordPrompt = false
                            if let url = pendingEncryptedURL {
                                importEncryptedBackup(from: url)
                            }
                        } label: {
                            Text("Decrypt & Import")
                        }
                        .buttonStyle(SettingsPrimaryButtonStyle())
                        .disabled(importPassword.isEmpty)
                    }
                    .padding(OffRecordSpacing.screenX)
                }
                .background(OffRecordColor.appBackgroundGradient)
                .navigationTitle("Encrypted Backup")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showPasswordPrompt = false
                            pendingEncryptedURL?.stopAccessingSecurityScopedResource()
                            pendingEncryptedURL = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert("Import Complete", isPresented: $showResult) {
            Button("OK") {
                if case .success = importResult {
                    dismiss()
                }
            }
        } message: {
            switch importResult {
            case .success(let count):
                Text("Successfully imported \(count) new entries.")
            case .error(let message):
                Text(message)
            case .none:
                Text("")
            }
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            if url.pathExtension.lowercased() == "dvx" {
                // Encrypted backup — prompt for password
                guard url.startAccessingSecurityScopedResource() else {
                    pendingEncryptedURL = nil
                    importPassword = ""
                    importResult = .error("Unable to access the selected file.")
                    showResult = true
                    return
                }
                pendingEncryptedURL = url
                importPassword = ""
                showPasswordPrompt = true
            } else {
                importBackup(from: url)
            }
        case .failure(let error):
            importResult = .error(error.localizedDescription)
            showResult = true
        }
    }

    private func importEncryptedBackup(from url: URL) {
        isImporting = true

        Task { @MainActor in
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let count = try BackupService.shared.importEncrypted(url: url, password: importPassword, context: viewContext)
                isImporting = false
                importResult = .success(count)
                showResult = true
                HapticManager.shared.entrySaved()
            } catch {
                isImporting = false
                importResult = .error("Failed to import: \(error.localizedDescription)")
                showResult = true
                HapticManager.shared.error()
            }
        }
    }

    private func importBackup(from url: URL) {
        isImporting = true
        
        // Start accessing security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            importResult = .error("Unable to access the selected file.")
            showResult = true
            isImporting = false
            return
        }
        
        Task { @MainActor in
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            do {
                let count = try BackupService.shared.importFromJSON(url: url, context: viewContext)
                isImporting = false
                importResult = .success(count)
                showResult = true
                HapticManager.shared.entrySaved()
            } catch {
                isImporting = false
                importResult = .error("Failed to import: \(error.localizedDescription)")
                showResult = true
                HapticManager.shared.error()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        BackupExportView(entries: [])
    }
}
