//
//  CaptureViews.swift
//  OffRecord
//
//  Voice capture surfaces: the tab bar accessory (available on every tab),
//  the expanded capture panel with a live waveform and transcript, and the
//  "Saved" moment with quick mood and undo.
//

import PhotosUI
import SwiftUI

// MARK: - Waveform

/// A rolling waveform built from recent input levels. Newest samples enter on the right.
struct CaptureWaveformView: View {
    let levels: [Float]
    var isActive: Bool = true
    var barCount: Int = 36
    var tint: Color = OffRecordColor.brandPlum
    var inactiveTint: Color = OffRecordColor.textTertiary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { context, size in
            let samples = displaySamples
            let spacing: CGFloat = max(2, size.width / CGFloat(barCount) * 0.38)
            let barWidth = max(2, (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
            for (index, sample) in samples.enumerated() {
                let normalized = CGFloat(max(0.06, min(1, sample)))
                let height = max(barWidth, size.height * normalized)
                let x = CGFloat(index) * (barWidth + spacing)
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                let recency = Double(index + 1) / Double(samples.count)
                let color = isActive ? tint.opacity(0.35 + 0.65 * recency) : inactiveTint.opacity(0.4)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }

    private var displaySamples: [Float] {
        if reduceMotion {
            // A calm, symmetric level meter instead of a scrolling trace.
            let current = levels.last ?? 0
            return (0..<barCount).map { index in
                let distance = abs(Float(index) - Float(barCount - 1) / 2) / (Float(barCount) / 2)
                return current * (1 - distance * 0.7)
            }
        }
        let recent = levels.suffix(barCount)
        let padding = Array(repeating: Float(0), count: max(0, barCount - recent.count))
        return padding + recent
    }
}

// MARK: - Tab bar accessory

/// Compact capture control shown above the tab bar on every tab.
struct CaptureAccessoryBar: View {
    @ObservedObject private var capture = CaptureController.shared
    @ObservedObject private var recorder = CaptureController.shared.recorder
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var photoItems: [PhotosPickerItem] = []

    let onWrite: () -> Void

    private var isInline: Bool { placement == .inline }

    var body: some View {
        HStack(spacing: OffRecordSpacing.sm) {
            switch capture.phase {
            case .idle, .saved:
                idleContent
            case .starting:
                startingContent
            case .recording, .paused:
                recordingContent
            }
        }
        .padding(.horizontal, OffRecordSpacing.sm)
        .frame(maxWidth: .infinity)
        .offRecordAnimation(OffRecordMotion.snappy, value: capture.phase)
    }

    private var idleContent: some View {
        Group {
            Button {
                capture.startRecording()
            } label: {
                HStack(spacing: OffRecordSpacing.sm) {
                    Image(systemName: "mic.fill")
                        .font(OffRecordTypography.labelMedium)
                        .foregroundStyle(OffRecordColor.textOnAccent)
                        .frame(width: 30, height: 30)
                        .background(OffRecordColor.brandPlum, in: Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Record")
                            .font(OffRecordTypography.labelMedium)
                            .foregroundStyle(OffRecordColor.textPrimary)
                        if !isInline && !capture.isCaptureDateToday {
                            // Text stays in the primary color so it reads on any glass backdrop;
                            // the small warm icon carries the other-day cue.
                            Label {
                                Text("For \(capture.captureDate.formatted(.dateTime.month(.abbreviated).day()))")
                                    .foregroundStyle(OffRecordColor.textPrimary)
                            } icon: {
                                Image(systemName: "calendar")
                                    .foregroundStyle(OffRecordColor.textWarm)
                                    .accessibilityHidden(true)
                            }
                            .labelStyle(.titleAndIcon)
                            .font(OffRecordTypography.annotation)
                        }
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Record")
            .accessibilityHint("Adds a recording to \(capture.isCaptureDateToday ? "today" : "that day")’s entry.")
            .accessibilityIdentifier("todayDock.record")

            if !isInline {
                PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
                    photoIcon
                        .frame(width: OffRecordLayout.minimumTapTarget, height: OffRecordLayout.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onChange(of: photoItems) { _, items in
                    capture.importPhotos(items)
                    photoItems = []
                }
                .accessibilityLabel("Add Photos")
                .accessibilityIdentifier("todayDock.photo")
            }

            Button(action: onWrite) {
                Image(systemName: "square.and.pencil")
                    .font(OffRecordTypography.titleSmall)
                    .foregroundStyle(OffRecordColor.textSage)
                    .frame(width: OffRecordLayout.minimumTapTarget, height: OffRecordLayout.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Write")
            .accessibilityIdentifier("todayDock.write")
        }
    }

    @ViewBuilder
    private var photoIcon: some View {
        switch capture.photoImport {
        case .importing:
            ProgressView()
                .controlSize(.small)
        case .imported:
            Image(systemName: "checkmark.circle.fill")
                .font(OffRecordTypography.titleSmall)
                .foregroundStyle(OffRecordColor.textSage)
                .transition(.scale.combined(with: .opacity))
        case .idle:
            Image(systemName: "photo.badge.plus")
                .font(OffRecordTypography.titleSmall)
                .foregroundStyle(OffRecordColor.textSage)
        }
    }

    private var startingContent: some View {
        HStack(spacing: OffRecordSpacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text("Starting…")
                .font(OffRecordTypography.labelMedium)
                .foregroundStyle(OffRecordColor.textSecondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var recordingContent: some View {
        Group {
            Button {
                capture.isPanelPresented = true
            } label: {
                HStack(spacing: OffRecordSpacing.sm) {
                    RecordingPulseDot(isPaused: capture.phase == .paused)
                    Text(CaptureFormat.clock(recorder.currentTime))
                        .font(OffRecordTypography.numberSmall)
                        .foregroundStyle(OffRecordColor.textPrimary)
                        .contentTransition(.numericText())
                    if !isInline {
                        CaptureWaveformView(
                            levels: recorder.levelHistory,
                            isActive: capture.phase == .recording,
                            barCount: 22,
                            tint: OffRecordColor.textCoral
                        )
                        .frame(height: 22)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(capture.phase == .paused ? "Recording paused" : "Recording")
            .accessibilityValue(CaptureFormat.spokenDuration(recorder.currentTime))
            .accessibilityHint("Opens recording controls.")

            Button {
                capture.finishRecording()
            } label: {
                Image(systemName: "stop.fill")
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textOnAccent)
                    .frame(width: 34, height: 34)
                    .background(OffRecordColor.textCoral, in: Circle())
                    .frame(width: OffRecordLayout.minimumTapTarget, height: OffRecordLayout.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop and Save")
            .accessibilityIdentifier("todayDock.stop")
        }
    }
}

struct RecordingPulseDot: View {
    var isPaused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isPaused {
                Image(systemName: "pause.fill")
                    .font(OffRecordTypography.annotation.weight(.bold))
                    .foregroundStyle(OffRecordColor.textWarm)
            } else {
                Circle()
                    .fill(OffRecordColor.brandCoral)
                    .frame(width: 10, height: 10)
                    .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.35]) { dot, opacity in
                        dot.opacity(opacity)
                    } animation: { _ in .easeInOut(duration: 0.8) }
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

// MARK: - Capture panel

/// The expanded capture experience: live recording, then the saved moment.
struct CapturePanelView: View {
    @ObservedObject private var capture = CaptureController.shared
    @ObservedObject private var recorder = CaptureController.shared.recorder

    var body: some View {
        ZStack {
            OffRecordColor.todayCaptureGradient
                .ignoresSafeArea()

            switch capture.phase {
            case .saved:
                if let saved = capture.savedCapture {
                    CaptureSavedView(saved: saved)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.96).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            case .idle:
                Color.clear
            case .starting, .recording, .paused:
                CaptureRecordingView()
                    .transition(.opacity)
            }
        }
        .offRecordAnimation(OffRecordMotion.hero, value: capture.phase)
        .onChange(of: recorder.wasInterrupted) { _, _ in
            capture.syncWithRecorderInterruption()
        }
        .captureAlerts(presentedInPanel: true)
    }
}

private struct CaptureRecordingView: View {
    @ObservedObject private var capture = CaptureController.shared
    @ObservedObject private var recorder = CaptureController.shared.recorder
    @State private var isConfirmingDiscard = false
    @State private var isChoosingDate = false

    private var isPaused: Bool { capture.phase == .paused }

    var body: some View {
        VStack(spacing: OffRecordSpacing.lg) {
            header

            Spacer(minLength: 0)

            VStack(spacing: OffRecordSpacing.sm) {
                Text(statusTitle)
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(isPaused ? OffRecordColor.textWarm : OffRecordColor.textCoral)
                    .contentTransition(.opacity)

                Text(CaptureFormat.clock(recorder.currentTime))
                    .font(OffRecordTypography.numberLarge)
                    .foregroundStyle(OffRecordColor.textHeading)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Elapsed time")
                    .accessibilityValue(CaptureFormat.spokenDuration(recorder.currentTime))

                if let prompt = capture.activePrompt {
                    Text(prompt)
                        .font(OffRecordTypography.bodyMedium)
                        .foregroundStyle(OffRecordColor.textBrand)
                        .multilineTextAlignment(.center)
                        .padding(.top, OffRecordSpacing.xs)
                }

                if recorder.wasInterrupted && isPaused {
                    Text("Paused. Another app used the microphone.")
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .multilineTextAlignment(.center)
                } else if recorder.currentTime >= CaptureController.longRecordingWarningSeconds {
                    Text("Long recording. Save and start a new one?")
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(OffRecordColor.textWarm)
                }
            }

            CaptureWaveformView(
                levels: recorder.levelHistory,
                isActive: capture.phase == .recording,
                barCount: 44,
                tint: OffRecordColor.brandPlum
            )
            .frame(height: 76)
            .padding(.horizontal, OffRecordSpacing.sm)

            transcriptArea

            Spacer(minLength: 0)

            controls
        }
        .padding(.horizontal, OffRecordSpacing.screenX)
        .padding(.top, OffRecordSpacing.xl)
        .padding(.bottom, OffRecordSpacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture.panel")
        .confirmationDialog(
            "Discard Recording?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                capture.discardRecording()
            }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("It hasn’t been saved yet.")
        }
    }

    private var statusTitle: String {
        switch capture.phase {
        case .starting: return "Starting…"
        case .paused: return "Paused"
        default: return "Recording"
        }
    }

    private var header: some View {
        HStack(spacing: OffRecordSpacing.sm) {
            Button {
                isChoosingDate = true
            } label: {
                Label(dateLabel, systemImage: "calendar")
                    .font(OffRecordTypography.labelSmall)
                    .offRecordReadablePill(capture.isCaptureDateToday ? .neutral : .journal, horizontalPadding: 12, verticalPadding: 8)
            }
            .buttonStyle(.plain)
            .frame(minHeight: OffRecordLayout.minimumTapTarget)
            .accessibilityLabel("Date, \(dateLabel)")
            .accessibilityHint("Changes the entry date.")
            .popover(isPresented: $isChoosingDate) {
                DatePicker("Date", selection: $capture.captureDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .frame(minWidth: 320)
                    .presentationCompactAdaptation(.popover)
            }

            Spacer(minLength: 0)

            if capture.isLiveTranscriptActive || SpeechTranscriptionConsent.hasGrantedAppleSpeechProcessing {
                Button {
                    withOffRecordAnimation(OffRecordMotion.snappy) {
                        capture.showsLiveTranscript.toggle()
                    }
                } label: {
                    Image(systemName: capture.showsLiveTranscript ? "captions.bubble.fill" : "captions.bubble")
                        .font(OffRecordTypography.titleSmall)
                        .foregroundStyle(OffRecordColor.textBrand)
                        .frame(width: OffRecordLayout.minimumTapTarget, height: OffRecordLayout.minimumTapTarget)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(capture.showsLiveTranscript ? "Hide Transcript" : "Show Transcript")
            }
        }
    }

    private var dateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(capture.captureDate) { return "Today" }
        if calendar.isDateInYesterday(capture.captureDate) { return "Yesterday" }
        return capture.captureDate.formatted(.dateTime.month(.abbreviated).day())
    }

    @ViewBuilder
    private var transcriptArea: some View {
        if capture.showsLiveTranscript && (capture.isLiveTranscriptActive || !capture.liveTranscript.isEmpty) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(capture.liveTranscript.isEmpty ? "Transcript appears here." : capture.liveTranscript)
                        .font(OffRecordTypography.journalBody)
                        .foregroundStyle(capture.liveTranscript.isEmpty ? OffRecordColor.textTertiary : OffRecordColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("transcript")
                        .textSelection(.enabled)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 140)
                .padding(OffRecordSpacing.lg)
                .background(OffRecordColor.surfacePrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous))
                .onChange(of: capture.liveTranscript) { _, _ in
                    proxy.scrollTo("transcript", anchor: .bottom)
                }
                .accessibilityLabel("Transcript")
                .accessibilityValue(capture.liveTranscript)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var controls: some View {
        HStack(spacing: OffRecordSpacing.xl) {
            CaptureRoundControl(
                systemImage: "trash",
                label: "Discard",
                style: .warning
            ) {
                if recorder.currentTime > 10 {
                    isConfirmingDiscard = true
                } else {
                    capture.discardRecording()
                }
            }
            .disabled(capture.phase == .starting)

            CaptureRoundControl(
                systemImage: isPaused ? "play.fill" : "pause.fill",
                label: isPaused ? "Resume" : "Pause",
                style: .journal
            ) {
                capture.togglePause()
            }
            .disabled(capture.phase == .starting)

            Button {
                capture.finishRecording()
            } label: {
                Label("Save", systemImage: "checkmark")
                    .font(OffRecordTypography.labelLarge)
                    .frame(maxWidth: .infinity)
                    .offRecordPillButton()
            }
            .buttonStyle(.plain)
            .disabled(capture.phase == .starting)
            .accessibilityLabel("Save recording")
            .accessibilityIdentifier("capture.save")
        }
    }
}

private struct CaptureRoundControl: View {
    let systemImage: String
    let label: String
    let style: OffRecordReadableTintStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: OffRecordSpacing.xs) {
                Image(systemName: systemImage)
                    .font(OffRecordTypography.titleSmall)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 56, height: 56)
                    .background(style.fill, in: Circle())
                    .overlay(Circle().stroke(style.border, lineWidth: 1))
                Text(label)
                    .font(OffRecordTypography.annotation)
            }
            .foregroundStyle(style.foreground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Saved moment

private struct CaptureSavedView: View {
    let saved: SavedCapture
    @ObservedObject private var capture = CaptureController.shared
    @ObservedObject private var health = HealthStateOfMindWriter.shared
    @ObservedObject private var router = OffRecordNavigationRouter.shared
    @State private var isShowingDial = false
    @State private var dialMood: Mood = .none
    @State private var showsHealthOffer = false
    @State private var didAppear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffRecordSpacing.xl) {
                header
                transcriptCard
                moodSection
                if showsHealthOffer {
                    healthOffer
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                actions
            }
            .padding(.horizontal, OffRecordSpacing.screenX)
            .padding(.vertical, OffRecordSpacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture.saved")
        .onAppear { didAppear = true }
        .fullScreenCover(isPresented: $isShowingDial) {
            MoodDialSheet(selectedMood: $dialMood) {
                if dialMood != .none {
                    choose(dialMood)
                }
            }
            .offRecordMoodDialEnvironment()
        }
        .simultaneousGesture(TapGesture().onEnded { capture.holdSavedCard() })
    }

    private var header: some View {
        HStack(spacing: OffRecordSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(OffRecordColor.textOnAccent, OffRecordColor.brandSageDark)
                .symbolEffect(.bounce, value: didAppear)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved to \(saved.dayLabel)")
                    .font(OffRecordTypography.titleMedium)
                    .foregroundStyle(OffRecordColor.textHeading)
                Text("\(CaptureFormat.shortDuration(saved.duration)) recording")
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
            }
            Spacer(minLength: 0)
            Button {
                capture.dismissSaved()
            } label: {
                Image(systemName: "xmark")
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .frame(width: OffRecordLayout.minimumTapTarget, height: OffRecordLayout.minimumTapTarget)
                    .background(OffRecordColor.surfacePrimary.opacity(0.7), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            switch saved.transcription {
            case .waiting, .transcribing:
                Label("Transcribing…", systemImage: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: true)
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textLavender)
                if !saved.livePreview.isEmpty {
                    Text(saved.livePreview)
                        .font(OffRecordTypography.bodyMedium)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .lineLimit(4)
                } else {
                    TranscriptPlaceholderLines()
                }
            case .done(let text):
                Label("Transcript", systemImage: "text.quote")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textLavender)
                Text(text.isEmpty ? "No speech detected. The recording is saved." : text)
                    .font(OffRecordTypography.bodyMedium)
                    .foregroundStyle(text.isEmpty ? OffRecordColor.textSecondary : OffRecordColor.textPrimary)
                    .lineLimit(5)
                    .transition(.opacity)
            case .needsConsent:
                Label("Transcription Off", systemImage: "waveform.slash")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textSecondary)
                Text("Turn it on to get text from recordings.")
                    .font(OffRecordTypography.bodySmall)
                    .foregroundStyle(OffRecordColor.textSecondary)
                Button("Transcribe") {
                    capture.grantSpeechConsentAndTranscribe()
                }
                .font(OffRecordTypography.labelMedium)
                .foregroundStyle(OffRecordColor.textLavender)
                .frame(minHeight: OffRecordLayout.minimumTapTarget)
            case .failed(let reason):
                Label("No Transcript", systemImage: "exclamationmark.bubble")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textWarm)
                Text("\(reason) The recording is saved.")
                    .font(OffRecordTypography.bodySmall)
                    .foregroundStyle(OffRecordColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OffRecordSpacing.lg)
        .offRecordCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfacePrimary.opacity(0.9), shadow: false)
        .offRecordAnimation(OffRecordMotion.gentle, value: saved.transcription)
        .accessibilityElement(children: .combine)
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            HStack {
                Text("How are you feeling?")
                    .font(OffRecordTypography.cardTitle)
                    .foregroundStyle(OffRecordColor.textHeading)
                Spacer()
                Button("More Moods") {
                    dialMood = saved.mood ?? .none
                    isShowingDial = true
                }
                .font(OffRecordTypography.labelSmall)
                .foregroundStyle(OffRecordColor.textLavender)
                .frame(minHeight: OffRecordLayout.minimumTapTarget)
            }

            MoodQuickStrip(selected: saved.mood) { mood in
                choose(mood)
            }
        }
    }

    private var healthOffer: some View {
        HStack(alignment: .top, spacing: OffRecordSpacing.md) {
            Image(systemName: "heart.text.square.fill")
                .font(OffRecordTypography.titleSmall)
                .foregroundStyle(OffRecordColor.textBlush)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                Text("Save moods to Apple Health?")
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textPrimary)
                Text("Only the mood and time are shared, never what you said.")
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                HStack(spacing: OffRecordSpacing.md) {
                    Button("Turn On") {
                        Task {
                            await health.setEnabled(true)
                            if let mood = saved.mood {
                                health.recordMomentaryMood(mood, at: saved.capturedAt)
                            }
                            withOffRecordAnimation { showsHealthOffer = false }
                        }
                    }
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textBlush)
                    Button("Not Now") {
                        health.markOffered()
                        withOffRecordAnimation { showsHealthOffer = false }
                    }
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textSecondary)
                }
                .frame(minHeight: OffRecordLayout.minimumTapTarget)
            }
        }
        .padding(OffRecordSpacing.lg)
        .offRecordCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceBlush, border: OffRecordColor.borderSoft, shadow: false)
    }

    private var actions: some View {
        HStack(spacing: OffRecordSpacing.md) {
            Button {
                capture.undoLastCapture()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textCoral, fill: OffRecordColor.surfacePrimary.opacity(0.8)))
            .accessibilityHint("Deletes this recording.")

            Button {
                let id = saved.entryID
                capture.dismissSaved()
                if let id {
                    router.route(.entry(id), canNavigate: true)
                }
            } label: {
                Label("Open", systemImage: "book.pages")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textBrand, fill: OffRecordColor.surfacePrimary.opacity(0.8)))
            .accessibilityLabel("Open Entry")

            Button {
                capture.dismissSaved()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textOnAccent, fill: OffRecordColor.brandPlum))
            .accessibilityIdentifier("capture.done")
        }
    }

    private func choose(_ mood: Mood) {
        capture.setMood(mood)
        if health.shouldOfferAfterMoodPick {
            withOffRecordAnimation { showsHealthOffer = true }
        }
    }
}

private struct TranscriptPlaceholderLines: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([1.0, 0.86, 0.6], id: \.self) { width in
                GeometryReader { proxy in
                    Capsule()
                        .fill(OffRecordColor.textTertiary.opacity(0.18))
                        .frame(width: proxy.size.width * width, height: 10)
                }
                .frame(height: 10)
            }
        }
        .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.45]) { lines, opacity in
            lines.opacity(opacity)
        } animation: { _ in .easeInOut(duration: 0.9) }
        .accessibilityHidden(true)
    }
}

/// One-tap mood picker using the shared mood artwork.
struct MoodQuickStrip: View {
    let selected: Mood?
    let onSelect: (Mood) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: OffRecordSpacing.sm) {
                ForEach(Mood.selectableMoods) { mood in
                    let isSelected = selected == mood
                    Button {
                        onSelect(mood)
                    } label: {
                        VStack(spacing: OffRecordSpacing.xs) {
                            mood.miniImage
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .scaleEffect(isSelected ? 1.12 : 1)
                            Text(mood.displayName)
                                .font(OffRecordTypography.annotation)
                                .foregroundStyle(isSelected ? mood.readableStyle.foreground : OffRecordColor.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, OffRecordSpacing.sm)
                        .frame(minWidth: 64)
                        .background {
                            RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous)
                                .fill(isSelected ? mood.readableStyle.fill : OffRecordColor.surfacePrimary.opacity(0.55))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous)
                                .stroke(isSelected ? mood.readableStyle.foreground.opacity(0.5) : OffRecordColor.borderSoft, lineWidth: isSelected ? 1.5 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mood.displayName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("capture.mood.\(mood.rawValue)")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .offRecordAnimation(OffRecordMotion.bouncy, value: selected)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// Soft capsule button used for secondary actions across capture and cards.
struct OffRecordSoftButtonStyle: ButtonStyle {
    var tint: Color = OffRecordColor.textBrand
    var fill: Color = OffRecordColor.surfacePrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OffRecordTypography.labelMedium)
            .foregroundStyle(tint)
            .frame(minHeight: 48)
            .padding(.horizontal, OffRecordSpacing.md)
            .background(fill, in: Capsule())
            .overlay(Capsule().stroke(OffRecordColor.borderSoft, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(OffRecordMotion.snappy, value: configuration.isPressed)
    }
}

// MARK: - Alerts

private struct CaptureAlertsModifier: ViewModifier {
    @ObservedObject private var capture = CaptureController.shared
    let presentedInPanel: Bool

    private var isHost: Bool {
        presentedInPanel == capture.isPanelPresented
    }

    func body(content: Content) -> some View {
        content
            .alert(
                capture.alert?.title ?? "",
                isPresented: Binding(
                    get: { isHost && capture.alert != nil },
                    set: { if !$0 { capture.alert = nil } }
                ),
                presenting: capture.alert
            ) { alert in
                if alert.offersSettingsLink {
                    Button("Open Settings") {
                        CaptureController.openSystemSettings()
                    }
                    Button("Not Now", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: { alert in
                Text(alert.message)
            }
            .alert(
                SpeechTranscriptionConsent.disclosureTitle,
                isPresented: Binding(
                    get: { isHost && capture.isSpeechConsentPromptPresented },
                    set: { capture.isSpeechConsentPromptPresented = $0 }
                )
            ) {
                Button("Transcribe") {
                    capture.grantSpeechConsentAndTranscribe()
                }
                Button("Not Now", role: .cancel) {
                    capture.declineSpeechConsent()
                }
            } message: {
                Text(SpeechTranscriptionConsent.disclosureMessage)
            }
    }
}

extension View {
    /// Hosts capture alerts. The panel hosts them while it's open; the root otherwise.
    func captureAlerts(presentedInPanel: Bool = false) -> some View {
        modifier(CaptureAlertsModifier(presentedInPanel: presentedInPanel))
    }
}

// MARK: - Formatting

enum CaptureFormat {
    static func clock(_ time: TimeInterval) -> String {
        let total = Int(time.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func shortDuration(_ time: TimeInterval) -> String {
        let total = max(1, Int(time.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        if minutes == 0 { return "\(seconds)s" }
        return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
    }

    static func spokenDuration(_ time: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = time >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        return formatter.string(from: max(0, time)) ?? ""
    }
}
