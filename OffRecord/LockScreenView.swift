import SwiftUI

struct LockScreenView: View {
    @ObservedObject private var lockManager = AppLockManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var authFailed = false

    var body: some View {
        ZStack {
            OffRecordColor.appBackgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: horizontalSizeClass == .regular ? 80 : 64))
                    .foregroundColor(OffRecordColor.brandSageDark)

                Text("OffRecord AI Journal is Locked")
                    .font(.title2.bold())
                    .foregroundColor(OffRecordColor.textHeading)

                Text("Only you can unlock and see your entries.")
                    .font(.subheadline)
                    .foregroundColor(OffRecordColor.textSecondary)
                    .multilineTextAlignment(.center)

                Button(action: unlock) {
                    HStack {
                        Image(systemName: lockManager.biometricsAvailable ? biometryIcon : "key.fill")
                        Text("Unlock with \(lockManager.biometryTypeName)")
                    }
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: 320)
                    .foregroundColor(OffRecordColor.textInverse)
                    .background(OffRecordColor.brandSageDark, in: Capsule())
                }

                if authFailed {
                    Text("Authentication failed. Please try again.")
                        .font(.caption)
                        .foregroundColor(OffRecordColor.textCoral)
                }
            }
            .frame(maxWidth: 500)
            .padding(OffRecordSpacing.xxl)
            .offRecordContentCard(cornerRadius: OffRecordRadius.xl, fill: OffRecordColor.surfaceWarm)
            .padding()
        }
        .onAppear {
            // Auto-prompt on appear
            unlock()
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
        lockManager.authenticate { success in
            authFailed = !success
        }
    }
}
