//
//  StoreRecoveryView.swift
//  OffRecord
//
//  Shown in place of the app when the journal store doesn't open. It says
//  what happened and offers Try Again, Export a Copy (the raw store files),
//  and Contact Support. It never deletes or replaces the store.
//

import SwiftUI

struct StoreRecoveryView: View {
    static let supportEmail = "saransh1337@gmail.com"

    @ObservedObject var session: PersistenceStoreSession
    @Environment(\.openURL) private var openURL
    @State private var isRetrying = false
    @State private var retryFailed = false
    @State private var exportURL: URL?
    @State private var showsExportError = false

    var body: some View {
        ScrollView {
            VStack(spacing: OffRecordSpacing.xxl) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(OffRecordTypography.screenTitle)
                    .imageScale(.large)
                    .foregroundStyle(OffRecordColor.textPeach)
                    .accessibilityHidden(true)

                VStack(spacing: OffRecordSpacing.sm) {
                    Text("Couldn’t Open Your Entries")
                        .font(OffRecordTypography.titleMedium)
                        .foregroundStyle(OffRecordColor.textHeading)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text("The file that holds your entries didn’t open. Nothing was deleted.")
                        .font(OffRecordTypography.bodySmall)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if let failure = session.loadFailure {
                        Text("Code: \(failure.reference)", comment: "Store recovery: the error code, for support")
                            .font(OffRecordTypography.annotation)
                            .foregroundStyle(OffRecordColor.textTertiary)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("storeRecovery.code")
                    }
                }

                VStack(spacing: OffRecordSpacing.md) {
                    Button(action: tryAgain) {
                        if isRetrying {
                            ProgressView()
                        } else {
                            Text("Try Again")
                        }
                    }
                    .buttonStyle(SettingsPrimaryButtonStyle())
                    .disabled(isRetrying)
                    .accessibilityIdentifier("storeRecovery.tryAgain")

                    if retryFailed {
                        Text("Export a copy, then contact support.", comment: "Store recovery: Try Again didn't help")
                            .font(OffRecordTypography.metadata)
                            .foregroundStyle(OffRecordColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("storeRecovery.stillFailing")
                    }

                    Button(action: exportCopy) {
                        Label("Export a Copy", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(SettingsSecondaryButtonStyle(tint: OffRecordColor.textSky, fill: OffRecordColor.surfaceBlue))
                    .accessibilityIdentifier("storeRecovery.export")

                    Button(action: contactSupport) {
                        Label("Contact Support", systemImage: "envelope")
                    }
                    .buttonStyle(SettingsSecondaryButtonStyle(tint: OffRecordColor.textBrand, fill: OffRecordColor.surfacePrimary))
                    .accessibilityIdentifier("storeRecovery.contactSupport")
                }
                .frame(maxWidth: 360)
            }
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, OffRecordSpacing.screenX)
            .padding(.vertical, OffRecordSpacing.section)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(OffRecordAppBackground())
        .accessibilityIdentifier("storeRecovery.screen")
        .sheet(item: Binding(
            get: { exportURL.map { IdentifiableURL(url: $0) } },
            set: { if $0 == nil { exportURL = nil } }
        )) { item in
            ShareSheet(activityItems: [item.url])
        }
        .alert(String(localized: "Couldn’t Export"), isPresented: $showsExportError) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text("Restart OffRecord, then try again.")
        }
    }

    private func tryAgain() {
        isRetrying = true
        Task { @MainActor in
            // Give the spinner a frame, so a quick failure still reads as a retry.
            try? await Task.sleep(for: .milliseconds(300))
            let opened = session.retry()
            isRetrying = false
            retryFailed = !opened
        }
    }

    private func exportCopy() {
        let storeURL = session.loadFailure?.storeURL ?? session.configuration.storeURL
        do {
            exportURL = try StoreFileCopier.makeShareableArchive(of: storeURL)
        } catch {
            showsExportError = true
        }
    }

    private func contactSupport() {
        guard let url = Self.supportMailURL(reference: session.loadFailure?.reference) else { return }
        openURL(url)
    }

    /// A mailto link with the error code and app version only; no journal content.
    static func supportMailURL(reference: String?, bundle: Bundle = .main) -> URL? {
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "OffRecord didn’t open my entries"),
            URLQueryItem(name: "body", value: "Code: \(reference ?? "unknown")\nOffRecord \(version)"),
        ]
        return components.url
    }
}
