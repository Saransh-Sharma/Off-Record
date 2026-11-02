//
//  Settings+Sync.swift
//  OffRecord
//
//  Settings › iCloud Sync: the switch, what it does to data in iCloud, and
//  live status (last sync, syncing now, the last error, the iCloud account).
//  The switch reopens the store in place; see PersistenceStoreSession.
//

import SwiftUI

struct SyncSettingsSection: View {
    static let searchKeywords = "icloud sync cloud devices status account"

    @ObservedObject private var monitor = CloudSyncMonitor.shared
    @ObservedObject private var session = PersistenceController.shared.session
    @ObservedObject private var capture = CaptureController.shared
    @AppStorage(PersistenceStoreConfiguration.syncPreferenceKey) private var isEnabled = true
    @State private var isSwitching = false
    @State private var alert: SyncSwitchAlert?
    @State private var needsRestart = false

    var body: some View {
        SettingsCard(
            title: String(localized: "iCloud Sync"),
            subtitle: subtitle,
            footer: footer,
            systemImage: isEnabled && summary != .signInRequired ? "icloud.fill" : "icloud.slash",
            tint: isEnabled && summary != .signInRequired ? OffRecordColor.textSky : OffRecordColor.textTertiary,
            fill: OffRecordColor.surfaceBlue
        ) {
            Toggle(isOn: Binding(get: { isEnabled }, set: switchSync)) {
                Text("iCloud Sync")
            }
            .disabled(isSwitching || capture.phase.isCapturing)
            .accessibilityIdentifier("settings.iCloud.toggle")

            statusRows
        }
        .accessibilityIdentifier("settings.iCloud.section")
        .alert(item: $alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .cancel(Text("OK")))
        }
        .onAppear {
            if monitor.switchDidNotApply {
                monitor.switchDidNotApply = false
                alert = .didNotChange
            }
        }
        // Mirroring that never starts after the switch means the live change didn't take.
        .task(id: monitor.mirroringStartRequestedAt) {
            guard monitor.mirroringStartRequestedAt != nil else { return }
            try? await Task.sleep(for: .seconds(21))
            needsRestart = monitor.mirroringLooksStalled()
        }
    }

    private var summary: CloudSyncStatus.Summary {
        monitor.status.summary(isEnabled: isEnabled)
    }

    private var subtitle: String {
        switch summary {
        case .off: return String(localized: "Off", comment: "iCloud Sync status: turned off")
        case .signInRequired: return String(localized: "Not Signed In", comment: "iCloud Sync status: no iCloud account")
        case .accountRestricted: return String(localized: "Restricted", comment: "iCloud Sync status: iCloud is limited by a restriction")
        case .syncing: return String(localized: "Syncing…", comment: "iCloud Sync status: sync in progress")
        case .problem: return String(localized: "Couldn’t Sync", comment: "iCloud Sync status: the last sync failed")
        case .synced, .waiting: return String(localized: "On", comment: "iCloud Sync status: turned on")
        }
    }

    /// The one place Settings says what the switch does to data in iCloud.
    private var footer: String {
        isEnabled
            ? String(localized: "Recordings stay on this \(DeviceNoun.current) and don’t sync. Turning sync off leaves entries here and in iCloud.")
            : String(localized: "Turning sync on copies entries on this \(DeviceNoun.current) to your iCloud. Recordings don’t sync.")
    }

    @ViewBuilder
    private var statusRows: some View {
        if isSwitching {
            SettingsRow(systemImage: "icloud", title: String(localized: "Updating…", comment: "iCloud Sync row while the switch applies"), tint: OffRecordColor.textSky) {
                ProgressView()
            }
        } else if needsRestart {
            warningRow(String(localized: "Restart OffRecord to finish turning on iCloud Sync."))
        } else {
            switch summary {
            case .off, .waiting:
                EmptyView()
            case .signInRequired:
                warningRow(CloudSyncProblem.notSignedIn.message)
            case .accountRestricted:
                warningRow(String(localized: "A restriction on this \(DeviceNoun.current) turns off iCloud."))
            case .syncing:
                SettingsRow(systemImage: "arrow.triangle.2.circlepath.icloud", title: String(localized: "Syncing…", comment: "iCloud Sync row: sync in progress"), tint: OffRecordColor.textSky) {
                    ProgressView()
                }
                .accessibilityIdentifier("settings.iCloud.syncing")
            case .problem(let problem):
                warningRow(problem.message)
                    .accessibilityIdentifier("settings.iCloud.problem")
            case .synced(let date):
                SettingsRow(systemImage: "checkmark.icloud", title: String(localized: "Last Synced", comment: "iCloud Sync row: when sync last finished"), tint: OffRecordColor.textSage) {
                    Text(date, format: .relative(presentation: .named))
                        .font(OffRecordTypography.bodySmall)
                        .foregroundColor(OffRecordColor.textPrimary)
                }
                .accessibilityIdentifier("settings.iCloud.lastSynced")
            }
        }
    }

    private func warningRow(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(OffRecordColor.textPeach)
                .font(OffRecordTypography.metadata)
                .accessibilityHidden(true)
            Text(message)
                .font(OffRecordTypography.metadata)
                .foregroundColor(OffRecordColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func switchSync(_ enabled: Bool) {
        guard enabled != isEnabled, !isSwitching else { return }
        if capture.phase.isCapturing || capture.savedCapture != nil {
            alert = .finishRecording
            return
        }
        isSwitching = true
        needsRestart = false
        // Let the switch animate before the screens rebuild around it.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            let outcome = PersistenceController.shared.setCloudSyncEnabled(enabled)
            // A reopen rebuilds every screen, so what happens next is kept in the monitor.
            isSwitching = false
            switch outcome {
            case .reloaded:
                monitor.noteSwitchApplied(mirroring: enabled)
            case .busy:
                alert = .busy
            case .keptPreviousSetting, .failed:
                monitor.noteSwitchDidNotApply()
            }
        }
    }
}

private enum SyncSwitchAlert: String, Identifiable {
    case finishRecording
    case busy
    case didNotChange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .finishRecording: return String(localized: "Finish Recording First")
        case .busy: return String(localized: "Try Again in a Moment")
        case .didNotChange: return String(localized: "iCloud Sync Didn’t Change")
        }
    }

    var message: String {
        switch self {
        case .finishRecording: return String(localized: "iCloud Sync can change once the recording is saved.")
        case .busy: return String(localized: "iCloud Sync can change once OffRecord finishes saving.")
        case .didNotChange: return String(localized: "Restart OffRecord, then try again.")
        }
    }
}
