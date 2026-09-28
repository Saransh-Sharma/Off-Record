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

            // Scrolls only when larger text sizes need the room.
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    voiceOrb
                    dictationCard

                    actionRow
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }
            .scrollBounceBehavior(.basedOnSize)

            if saved {
                SaveConfirmationToast(title: "Saved")
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // A toolbar item sits beside the system clock instead of underneath it.
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    cancelAndDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(WatchPalette.lavenderText)
                }
                .accessibilityLabel("Cancel")
            }
        }
        .onAppear(perform: startIfNeeded)
        .onDisappear(perform: cleanupIfNeeded)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: recorder.isRecording)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: saved)
        .accessibilityLabel("Speak")
    }

    /// Title, prompt, and elapsed time share one row below the system clock.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(recorder.isRecording ? "Listening" : "Speak")
                    .font(.headline)
                    .foregroundStyle(WatchPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Say what’s on your mind.")
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 4)

            Text(format(duration))
                .font(.headline.monospacedDigit())
                .foregroundStyle(WatchPalette.text)
                .lineLimit(1)
                .layoutPriority(1)
                .accessibilityLabel("Recording time \(format(duration))")
        }
    }

    private var voiceOrb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32)
                .fill(WatchPalette.lavenderSurface.opacity(0.96))
                .frame(height: 64)
                .overlay {
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(.white.opacity(0.42), lineWidth: 1)
                }
                .shadow(color: WatchPalette.lavender.opacity(recorder.isRecording ? 0.36 : 0.16), radius: recorder.isRecording ? 14 : 7)
            waveform
        }
        .scaleEffect(recorder.isRecording && !reduceMotion ? 1.02 : 1)
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
        .frame(height: 56)
        .accessibilityHidden(true)
    }

    private var dictationCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(cardTitle, systemImage: cardSymbol)
                .font(.caption.bold())
                .foregroundStyle(WatchPalette.lavenderText)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            if let cardMessage {
                Text(cardMessage)
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.lavenderText.opacity(0.82))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }
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
            .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")

            WatchPrimaryButton(
                title: saved ? "Saved" : "Save",
                systemImage: saved ? "checkmark.circle.fill" : "tray.and.arrow.down.fill",
                fill: WatchPalette.sageSurface,
                foreground: WatchPalette.sageText,
                isDisabled: isSaving || saved || !canSave,
                minHeight: 34,
                action: saveVoice
            )
            .accessibilityLabel("Save")
        }
    }

    private var cardTitle: String {
        if saved { return "Saved" }
        if pendingRecording != nil { return "Ready to save" }
        if recorder.isRecording { return "Recording" }
        if recorder.errorMessage != nil { return "Try again" }
        return "Speak now"
    }

    private var cardSymbol: String {
        if saved { return "checkmark.circle.fill" }
        if recorder.errorMessage != nil { return "exclamationmark.circle.fill" }
        return "text.bubble.fill"
    }

    private var cardMessage: String? {
        if let message = recorder.errorMessage {
            return message
        }
        if recorder.didReachSoftLimit {
            return "Almost at the limit."
        }
        if pendingRecording != nil || recorder.isRecording {
            return "Transcribed on iPhone."
        }
        return nil
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
        return min(56, max(10, CGFloat(recorder.level) * multipliers[offset] * 46))
    }

    private func format(_ time: TimeInterval) -> String {
        let total = Int(time)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
