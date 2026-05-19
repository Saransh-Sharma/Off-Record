import SwiftUI

struct HomePrivacyExplanationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                OffRecordIconBubble(
                    systemImage: "lock.shield.fill",
                    tint: OffRecordColor.brandSageDark,
                    fill: OffRecordColor.backgroundSageTint,
                    size: 58,
                    iconSize: 24
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Private by design")
                        .font(OffRecordTypography.titleMedium)
                        .foregroundStyle(OffRecordColor.textBrand)

                    Text("Your journal entries stay on this device. OffRecord uses local processing for private reflection features whenever possible, so your most personal notes are treated as yours first.")
                        .font(OffRecordTypography.bodyLarge)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .lineSpacing(3)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Entries are stored locally", systemImage: "iphone")
                    Label("Private AI context stays personal", systemImage: "sparkles")
                    Label("You control what gets exported", systemImage: "square.and.arrow.up")
                }
                .font(OffRecordTypography.labelMedium)
                .foregroundStyle(OffRecordColor.textSage)

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
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
