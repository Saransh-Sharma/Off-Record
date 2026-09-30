import SwiftUI

struct LockScreenView: View {
    @ObservedObject private var lockManager = AppLockManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var authFailed = false
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            OffRecordAppBackground()
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(horizontalSizeClass == .regular ? .largeTitle : .title, design: .rounded, weight: .semibold))
                    .imageScale(.large)
                    .foregroundStyle(OffRecordColor.textSage)
                    .symbolEffect(.bounce, value: authFailed)
                    .accessibilityHidden(true)

                Text("Journal Locked")
                    .font(OffRecordTypography.titleMedium)
                    .foregroundColor(OffRecordColor.textHeading)
                    .accessibilityAddTraits(.isHeader)

                Button(action: unlock) {
                    HStack {
                        Image(systemName: lockManager.biometricsAvailable ? biometryIcon : "key.fill")
                        Text("Unlock with \(lockManager.biometryTypeName)")
                    }
                    .frame(maxWidth: 320)
                    .offRecordPrivacyButton()
                }
                .accessibilityLabel("Unlock with \(lockManager.biometryTypeName)")
                .accessibilityIdentifier("lockScreen.unlockButton")
                .disabled(isAuthenticating)

                if authFailed {
                    Text("Couldn’t unlock. Try again.")
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textCoral)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: 500)
            .padding(OffRecordSpacing.xxl)
            .offRecordContentCard(cornerRadius: OffRecordRadius.xl, fill: OffRecordColor.surfaceWarm)
            .padding()
        }
        .offRecordAnimation(OffRecordMotion.snappy, value: authFailed)
        .sensoryFeedback(.error, trigger: authFailed) { _, failed in failed }
        .onAppear {
            // Auto-prompt on appear
            unlock()
        }
        .onChange(of: scenePhase) { _, phase in
            // The lock view stays mounted while backgrounded, so prompt again on return.
            if phase == .active, !lockManager.isUnlocked {
                unlock()
            }
        }
    }

    private var biometryIcon: String {
        switch lockManager.biometryTypeName {
        case "Face ID": return "faceid"
        case "Touch ID": return "touchid"
        case "Optic ID": return "opticid"
        default: return "key.fill"
        }
    }

    private func unlock() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        lockManager.authenticate { success in
            isAuthenticating = false
            authFailed = !success
        }
    }
}

/// Covers journal content in the app switcher snapshot when the privacy lock is on.
struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            OffRecordAppBackground()
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: OffRecordSpacing.md) {
                Image(systemName: "lock.shield.fill")
                    .font(OffRecordTypography.titleLarge)
                    .foregroundStyle(OffRecordColor.textSage)
                Text("OffRecord")
                    .font(OffRecordTypography.titleSmall)
                    .foregroundStyle(OffRecordColor.textHeading)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
