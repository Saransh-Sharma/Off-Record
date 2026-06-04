import SwiftUI

struct WatchSpeakCaptureView: View {
    @ObservedObject var store: WatchCaptureStore
    let source: WatchCaptureSourceSurface

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var recorder = WatchAudioRecorder()
    @State private var pendingRecording: (url: URL, duration: TimeInterval)?
    @State private var saved = false
    @State private var isSaving = false
    @State private var didRequestStart = false

    private var duration: TimeInterval {
        pendingRecording?.duration ?? recorder.currentTime
    }

    private var canSave: Bool {
        recorder.isRecording || pendingRecording != nil
    }

    var body: some View {
        ZStack {
            WatchScreenBackground(mood: .lavender)

            VStack(alignment: .leading, spacing: 5) {
                topBar
                voiceOrb
                dictationCard

                actionRow
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            if saved {
                SaveConfirmationToast(title: "Saved")
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: startIfNeeded)
        .onDisappear(perform: cleanupIfNeeded)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: recorder.isRecording)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: saved)
        .accessibilityLabel("Start dictation")
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                cancelAndDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .frame(width: 30, height: 30)
                    .foregroundStyle(WatchPalette.lavenderText)
                    .background(WatchPalette.lavenderSurface, in: Circle())
            }
            .buttonStyle(WatchPressButtonStyle())
            .accessibilityLabel("Cancel")

            VStack(alignment: .leading, spacing: 1) {
                Text(recorder.isRecording ? "Listening" : "Speak")
                    .font(.callout.bold())
                    .foregroundStyle(WatchPalette.text)
                    .lineLimit(1)
                Text("Say what's on your mind.")
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
            .frame(maxWidth: 128, alignment: .leading)

            Spacer(minLength: 0)
        }
    }

    private var voiceOrb: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 34)
                    .fill(WatchPalette.lavenderSurface.opacity(0.96))
                    .frame(height: 72)
                    .overlay {
                        RoundedRectangle(cornerRadius: 34)
                            .stroke(.white.opacity(0.42), lineWidth: 1)
                    }
                    .shadow(color: WatchPalette.lavender.opacity(recorder.isRecording ? 0.36 : 0.16), radius: recorder.isRecording ? 14 : 7)
                waveform
            }
            .scaleEffect(recorder.isRecording && !reduceMotion ? 1.02 : 1)

            Text(format(duration))
                .font(.headline.monospacedDigit().bold())
                .foregroundStyle(WatchPalette.text)
                .accessibilityLabel("Recording time \(format(duration))")
        }
        .frame(maxWidth: .infinity)
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<11, id: \.self) { offset in
                Capsule()
                    .fill(WatchPalette.lavenderText.opacity(recorder.isRecording ? 0.86 : 0.50))
                    .frame(width: 5, height: barHeight(offset))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: recorder.level)
            }
        }
        .frame(height: 54)
        .accessibilityHidden(true)
    }

    private var dictationCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(cardTitle, systemImage: cardSymbol)
                .font(.caption.bold())
                .foregroundStyle(WatchPalette.lavenderText)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Text(cardMessage)
                .font(.caption2)
                .foregroundStyle(WatchPalette.lavenderText.opacity(0.82))
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
        .padding(8)
        .background(WatchPalette.lavenderSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.48), lineWidth: 1)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            WatchSecondaryButton(
                title: recorder.isRecording ? "Stop" : "Start",
                systemImage: recorder.isRecording ? "stop.fill" : "mic.fill",
                minHeight: 34,
                action: toggleRecording
            )
            .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start dictation")

            WatchPrimaryButton(
                title: saved ? "Saved" : "Save",
                systemImage: saved ? "checkmark.circle.fill" : "tray.and.arrow.down.fill",
                fill: WatchPalette.sageSurface,
                foreground: WatchPalette.sageText,
                isDisabled: isSaving || saved || !canSave,
                minHeight: 34,
                action: saveVoice
            )
            .accessibilityLabel("Save journal capture")
        }
    }

    private var cardTitle: String {
        if saved { return "Saved privately" }
        if pendingRecording != nil { return "Ready to save" }
        if recorder.isRecording { return "Voice moment" }
        if recorder.errorMessage != nil { return "Try again" }
        return "Start speaking"
    }

    private var cardSymbol: String {
        if saved { return "checkmark.circle.fill" }
        if recorder.errorMessage != nil { return "exclamationmark.circle.fill" }
        return "text.bubble.fill"
    }

    private var cardMessage: String {
        if let message = recorder.errorMessage {
            return message
        }
        if recorder.didReachSoftLimit {
            return "Finish soon to keep this light."
        }
        if pendingRecording != nil {
            return "Transcript later on iPhone."
        }
        if recorder.isRecording {
            return "Transcript later on iPhone."
        }
        return "Tap Start and speak naturally."
    }

    private func startIfNeeded() {
        guard !didRequestStart, !saved else { return }
        didRequestStart = true
        recorder.onHardLimitReached = { result in
            pendingRecording = result
            WatchHaptics.warning()
        }
        recorder.start()
    }

    private func toggleRecording() {
        if recorder.isRecording {
            pendingRecording = recorder.stop()
        } else if pendingRecording == nil {
            recorder.start()
        }
    }

    private func saveVoice() {
        guard !isSaving, !saved else { return }
        let recording = pendingRecording ?? recorder.stop()
        guard let recording else { return }
        pendingRecording = nil
        isSaving = true
        store.saveAudio(fileURL: recording.url, duration: recording.duration, source: source)
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
            dismiss()
        }
    }

    private func cancelAndDismiss() {
        cleanupIfNeeded()
        dismiss()
    }

    private func cleanupIfNeeded() {
        if recorder.isRecording && !saved {
            recorder.cancel()
        }
        if !saved, let pendingRecording {
            try? FileManager.default.removeItem(at: pendingRecording.url)
            self.pendingRecording = nil
        }
    }

    private func barHeight(_ offset: Int) -> CGFloat {
        let restingHeights: [CGFloat] = [10, 18, 28, 42, 58, 34, 52, 38, 24, 16, 10]
        if pendingRecording != nil || saved {
            return restingHeights[offset]
        }
        guard recorder.isRecording else {
            return restingHeights[offset] * 0.58
        }
        let multipliers: [CGFloat] = [0.52, 0.72, 1.0, 1.28, 1.54, 1.12, 1.42, 1.06, 0.84, 0.66, 0.48]
        return max(10, CGFloat(recorder.level) * multipliers[offset] * 54)
    }

    private func format(_ time: TimeInterval) -> String {
        let total = Int(time)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
