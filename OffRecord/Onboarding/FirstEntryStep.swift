//
//  FirstEntryStep.swift
//  OffRecord
//
//  Onboarding step 5: the first entry, recorded or typed when the microphone
//  is off, and how you are feeling.
//

import SwiftUI

enum FirstEntryMode {
    case voice
    case textFallback
}

struct FirstEntryStep: View {
    @ObservedObject var recorder: AudioRecorder
    let isRecording: Bool
    let isTranscribing: Bool
    let elapsedTime: TimeInterval
    let level: Float
    @Binding var draft: String
    @Binding var selectedMood: Mood
    let mode: FirstEntryMode
    let entryCreated: Bool
    let onRecordTap: () -> Void

    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        OnboardingQuestion(
            subtitle: String(localized: "A sentence is enough."),
            contentSpacing: 16
        ) {
            VStack(spacing: 18) {
                switch mode {
                case .voice:
                    voiceRecorder
                case .textFallback:
                    textFallbackEditor
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("How are you feeling?")
                        .font(OffRecordTypography.sectionTitle)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(Mood.selectableMoods.prefix(6)) { mood in
                            let isSelected = selectedMood == mood
                            Button {
                                HapticManager.shared.moodSelected()
                                selectedMood = mood
                            } label: {
                                OnboardingSelectableContainer(isSelected: isSelected, cornerRadius: 14, padding: 12) {
                                    HStack(spacing: 10) {
                                        MiniMoodIcon(
                                            mood: mood,
                                            size: 20,
                                            opacity: isSelected ? 1 : 0.72
                                        )
                                        Text(mood.displayName)
                                            .font(isSelected ? OffRecordTypography.labelLarge : OffRecordTypography.labelMedium)
                                            .foregroundStyle(OnboardingPalette.foreground)
                                        Spacer()
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(OffRecordTypography.labelMedium)
                                                .foregroundStyle(OnboardingPalette.foreground)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onAppear {
            focusTextEditorIfNeeded()
        }
        .onChange(of: mode) { _, _ in
            focusTextEditorIfNeeded()
        }
    }

    private var voiceRecorder: some View {
        Button(action: onRecordTap) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isRecording ? OffRecordColor.textCoral : OnboardingPalette.surface)
                        .frame(width: 104, height: 104)
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(.largeTitle, weight: .bold))
                        .foregroundStyle(isRecording ? OffRecordColor.textInverse : OffRecordColor.textAqua)
                }

                if isRecording {
                    Text(formatTime(elapsedTime))
                        .font(OffRecordTypography.numberMedium)
                    WaveformMeter(level: level)
                    Text("Recording")
                        .font(OffRecordTypography.labelMedium)
                        .foregroundStyle(OnboardingPalette.secondaryForeground)
                } else if isTranscribing {
                    ProgressView("Transcribing…")
                        .tint(OnboardingPalette.foreground)
                        .foregroundStyle(OnboardingPalette.foreground)
                } else if entryCreated {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(OffRecordTypography.sectionTitle)
                        .foregroundStyle(OnboardingPalette.foreground)
                } else {
                    Text("Record", comment: "Button that starts a voice recording")
                        .font(OffRecordTypography.sectionTitle)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(OnboardingPalette.surfaceSoft)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isRecording ? OffRecordColor.textCoral : OnboardingPalette.border, lineWidth: isRecording ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isTranscribing)
    }

    private var textFallbackEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Write it down")
                .font(OffRecordTypography.sectionTitle)
            TextField("Today I…", text: $draft, axis: .vertical)
                .focused($isTextEditorFocused)
                .id(OnboardingScrollTarget.firstEntryTextField)
                .accessibilityIdentifier("onboarding.firstEntry.textField")
                .foregroundColor(OffRecordColor.textPrimary)
                .lineLimit(6...10)
                .frame(minHeight: 160)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(14)
                .background(OnboardingPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .onAppear {
            focusTextEditorIfNeeded()
        }
    }

    private func focusTextEditorIfNeeded() {
        guard mode == .textFallback else {
            isTextEditorFocused = false
            return
        }

        [0.1, 0.45, 0.8].forEach { delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                isTextEditorFocused = true
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct WaveformMeter: View {
    let level: Float

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<18, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(OnboardingPalette.foreground)
                    .frame(width: 4, height: barHeight(index))
                    .opacity(indexOpacity(index))
            }
        }
        .frame(height: 34)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let normalized = CGFloat(max(0.12, min(1, level)))
        let wave = CGFloat(sin(Double(index) * 0.55 + Date().timeIntervalSince1970 * 7) * 0.28 + 0.72)
        return 8 + normalized * wave * 24
    }

    private func indexOpacity(_ index: Int) -> Double {
        let threshold = Double(index) / 18.0
        return Double(level) > threshold ? 1 : 0.35
    }
}
