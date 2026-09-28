//
//  BackupExportView.swift
//  OffRecord
//
//  Export and restore screens for journal backups and readable files.
//

import SwiftUI
import UniformTypeIdentifiers
import os.log

private let backupLogger = Logger(subsystem: "com.singularity.offrecord", category: "Backup")

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
        case .json, .encryptedBackup:
            return String(localized: "Backups include every entry.")
        default:
            return String(AttributedString(localized: "^[\(filteredEntryCount) entry](inflect: true)").characters)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
                SettingsCard(
                    title: String(localized: "Format", comment: "Export section: file format"),
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
                                title: format.title,
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
                    .accessibilityLabel(format.title)
                    .accessibilityHint(format.description)
                    .accessibilityAddTraits(selectedFormat == format ? [.isSelected] : [])
                }
            }
            
                SettingsCard(
                    title: String(localized: "Entries", comment: "Export filter section: which entries to include"),
                    footer: filterFooterText,
                    systemImage: "line.3.horizontal.decrease.circle",
                    tint: OffRecordColor.textAqua,
                    fill: OffRecordColor.surfaceMint
                ) {
                Toggle("All Entries", isOn: $includeAllEntries)
                
                if !includeAllEntries {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, displayedComponents: .date)
                }
                
                Toggle("Starred Only", isOn: $starredOnly)
            }
            .disabled(filtersAreDisabled)

            // Password fields for encrypted backup
            if selectedFormat == .encryptedBackup {
                    SettingsCard(
                        title: String(localized: "Password", comment: "Encrypted backup password section"),
                        footer: String(localized: "You’ll need this to restore. It can’t be recovered."),
                        systemImage: "lock.shield.fill",
                        tint: OffRecordColor.textSage,
                        fill: OffRecordColor.surfaceSage
                    ) {
                    SecureField("Password", text: $encryptionPassword)
                            .textFieldStyle(.roundedBorder)
                    SecureField("Confirm Password", text: $confirmPassword)
                            .textFieldStyle(.roundedBorder)

                    if !encryptionPassword.isEmpty && !confirmPassword.isEmpty && encryptionPassword != confirmPassword {
                        Text("Passwords don’t match")
                            .font(OffRecordTypography.metadata)
                            .foregroundColor(OffRecordColor.textCoral)
                    }
                }
            }

                Button {
                    exportData()
                } label: {
                    HStack(spacing: OffRecordSpacing.sm) {
                        if isExporting {
                            ProgressView()
                                .tint(OffRecordColor.textInverse)
                            Text("Exporting…")
                        } else {
                            Text("Export ^[\(filteredEntryCount) Entry](inflect: true)")
                        }
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
        .background(OffRecordAppBackground())
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn’t Export", isPresented: $showError) {
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
                backupLogger.error("Export failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    isExporting = false
                    errorMessage = String(localized: "Try again.")
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
                    title: String(localized: "Restore from Backup"),
                    subtitle: String(localized: "Choose a backup file exported from OffRecord."),
                    systemImage: "doc.badge.plus",
                    tint: OffRecordColor.textSky,
                    fill: OffRecordColor.surfaceBlue
                ) {
                    SettingsRow(systemImage: "checkmark.circle.fill", title: String(localized: "Entries you already have are skipped."), tint: OffRecordColor.textSage)
                    SettingsRow(systemImage: "arrow.triangle.merge", title: String(localized: "Nothing is deleted."), tint: OffRecordColor.textSky)
                    SettingsRow(systemImage: "icloud.and.arrow.up", title: String(localized: "Restored entries sync if iCloud is on."), tint: OffRecordColor.textLavender)
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
                        Text(isImporting ? String(localized: "Restoring…") : String(localized: "Choose Backup File"))
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
        .background(OffRecordAppBackground())
        .navigationTitle("Restore from Backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType.json, UTType(filenameExtension: "dvx") ?? UTType.data],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .sheet(isPresented: $showPasswordPrompt, onDismiss: cleanupPendingEncryptedImport) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
                        SettingsCard(
                            title: String(localized: "Encrypted Backup"),
                            subtitle: String(localized: "Enter this backup’s password."),
                            systemImage: "lock.shield.fill",
                            tint: OffRecordColor.textSage,
                            fill: OffRecordColor.surfaceSage
                        ) {
                        SecureField("Password", text: $importPassword)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button {
                            guard let url = pendingEncryptedURL else { return }
                            let password = importPassword
                            pendingEncryptedURL = nil
                            importPassword = ""
                            showPasswordPrompt = false
                            importEncryptedBackup(from: url, password: password)
                        } label: {
                            Text("Restore")
                        }
                        .buttonStyle(SettingsPrimaryButtonStyle())
                        .disabled(importPassword.isEmpty)
                    }
                    .padding(OffRecordSpacing.screenX)
                }
                .background(OffRecordAppBackground())
                .navigationTitle("Encrypted Backup")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showPasswordPrompt = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert(resultTitle, isPresented: $showResult) {
            Button("OK") {
                if case .success = importResult {
                    dismiss()
                }
            }
        } message: {
            switch importResult {
            case .success(let count):
                Text("^[\(count) entry](inflect: true) added.")
            case .error(let message):
                Text(message)
            case .none:
                Text("")
            }
        }
    }
    
    private var resultTitle: String {
        if case .error = importResult {
            return String(localized: "Couldn’t Restore")
        }
        return String(localized: "Restore Complete")
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
                    importResult = .error(String(localized: "Couldn’t open that file."))
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
            backupLogger.error("Backup file selection failed: \(error.localizedDescription, privacy: .public)")
            importResult = .error(String(localized: "Couldn’t open that file."))
            showResult = true
        }
    }

    private func cleanupPendingEncryptedImport() {
        pendingEncryptedURL?.stopAccessingSecurityScopedResource()
        pendingEncryptedURL = nil
        importPassword = ""
    }

    private func importEncryptedBackup(from url: URL, password: String) {
        isImporting = true

        Task { @MainActor in
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let count = try BackupService.shared.importEncrypted(url: url, password: password, context: viewContext)
                isImporting = false
                importResult = .success(count)
                showResult = true
                HapticManager.shared.entrySaved()
            } catch {
                backupLogger.error("Restore failed: \(error.localizedDescription, privacy: .public)")
                isImporting = false
                importResult = .error(String(localized: "Couldn’t restore. Check the password and try again."))
                showResult = true
                HapticManager.shared.error()
            }
        }
    }

    private func importBackup(from url: URL) {
        isImporting = true
        
        // Start accessing security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            importResult = .error(String(localized: "Couldn’t open that file."))
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
                backupLogger.error("Restore failed: \(error.localizedDescription, privacy: .public)")
                isImporting = false
                importResult = .error(String(localized: "Couldn’t restore this backup."))
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
