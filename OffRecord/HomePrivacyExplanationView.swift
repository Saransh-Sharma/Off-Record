import SwiftUI

struct HomePrivacyExplanationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    OffRecordIconBubble(
                        systemImage: "lock.shield.fill",
                        tint: OffRecordColor.brandSageDark,
                        fill: OffRecordColor.backgroundSageTint,
                        size: 58,
                        iconSize: 24
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your Privacy")
                            .font(OffRecordTypography.titleMedium)
                            .foregroundStyle(OffRecordColor.textBrand)

                        Text("Your entries, recordings, and transcripts are stored on this \(DeviceNoun.current). Transcription and Friday run here too, so nothing you write goes to a server.")
                            .font(OffRecordTypography.bodyLarge)
                            .foregroundStyle(OffRecordColor.textSecondary)
                            .lineSpacing(3)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Stored on your \(DeviceNoun.current)", systemImage: "iphone")
                        Label("Processed on your \(DeviceNoun.current)", systemImage: "sparkles")
                        Label("Leaves only when you export or turn on iCloud", systemImage: "square.and.arrow.up")
                    }
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textSage)

                    Spacer(minLength: 0)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(OffRecordColor.backgroundPrimary)
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }
}
