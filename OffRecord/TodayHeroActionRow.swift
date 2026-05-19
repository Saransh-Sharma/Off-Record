import SwiftUI

struct TodayHeroActionRow: View {
    let isRecording: Bool
    let isProcessing: Bool
    let onPrimary: () -> Void
    let onWrite: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                primaryButton
                writeButton
            }

            VStack(spacing: 12) {
                primaryButton
                writeButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var primaryButton: some View {
        Button(action: onPrimary) {
            Label(primaryTitle, systemImage: primarySymbolName)
                .font(OffRecordTypography.labelLarge)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(primaryFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(OffRecordColor.textInverse)
        .disabled(isProcessing)
        .accessibilityIdentifier("daypartHero.primaryCTA")
    }

    private var writeButton: some View {
        Button(action: onWrite) {
            Label("Write", systemImage: "square.and.pencil")
                .font(OffRecordTypography.labelLarge)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(OffRecordColor.surfacePrimary.opacity(0.94), in: Capsule())
                .overlay(Capsule().stroke(OffRecordColor.borderSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(OffRecordColor.textBrand)
        .disabled(isRecording || isProcessing)
        .accessibilityIdentifier("daypartHero.writeCTA")
    }

    private var primaryTitle: String {
        if isProcessing {
            return "Saving"
        }
        return isRecording ? "Stop recording" : "Start recording"
    }

    private var primarySymbolName: String {
        isRecording ? "stop.fill" : "mic.fill"
    }

    private var primaryFill: Color {
        if isRecording {
            return OffRecordColor.brandCoral
        }
        if isProcessing {
            return OffRecordColor.brandPeach
        }
        return OffRecordColor.brandPlum
    }
}
