import SwiftUI

@main
struct OffRecordWatchApp: App {
    @StateObject private var store = WatchCaptureStore.shared

    var body: some Scene {
        WindowGroup {
            QuickCaptureHomeView(store: store)
                .onAppear {
                    store.start()
                }
        }
    }
}

struct QuickCaptureHomeView: View {
    @ObservedObject var store: WatchCaptureStore
    @State private var path: [WatchHomeRoute] = []
    @State private var sourceSurface: WatchCaptureSourceSurface = .app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                LinearGradient(
                    colors: [WatchPalette.ink, WatchPalette.plum, Color(hex: 0x4C775B)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 9) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("OffRecord")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WatchPalette.secondary)
                        Text("Quick Capture")
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(WatchPalette.text)
                    }
                    .padding(.horizontal, 2)

                    Button {
                        path.append(.mood)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "face.smiling.fill")
                                .font(.title2.weight(.heavy))
                                .foregroundStyle(WatchPalette.sage)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Mood")
                                    .font(.headline.weight(.heavy))
                                Text("Spin the Crown")
                                    .font(.caption2)
                                    .foregroundStyle(WatchPalette.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "digitalcrown.horizontal.arrow.clockwise")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WatchPalette.secondary)
                        }
                        .foregroundStyle(WatchPalette.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 11)
                        .background(WatchPalette.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Choose a mood with touch or the Digital Crown.")

                    HStack(spacing: 7) {
                        tile("Speak", subtitle: "Dictate", symbol: "quote.bubble.fill", color: WatchPalette.lavender) {
                            path.append(.speak)
                        }
                        tile("Record", subtitle: "Voice", symbol: "record.circle", color: WatchPalette.peach) {
                            path.append(.record)
                        }
                    }

                    Button {
                        path.append(.recent)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text(store.queueCount == 0 ? "On your iPhone" : "Held for later")
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            Spacer(minLength: 0)
                            Text("\(store.queueCount)")
                                .font(.caption.monospacedDigit().weight(.bold))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WatchPalette.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(WatchPalette.surface.opacity(0.74), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    syncStatus
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .navigationDestination(for: WatchHomeRoute.self) { route in
                switch route {
                case .mood:
                    WatchMoodDialView(store: store, source: sourceSurface)
                case .speak:
                    WatchSpeakCaptureView(store: store, source: sourceSurface)
                case .record:
                    WatchRecordCaptureView(store: store, source: sourceSurface)
                case .recent:
                    WatchRecentCapturesView(store: store)
                case .home:
                    EmptyView()
                }
            }
            .onOpenURL { url in
                guard let route = WatchHomeRoute(url: url) else { return }
                sourceSurface = WatchHomeRoute.sourceSurface(from: url)
                path = route == .home ? [] : [route]
            }
        }
    }

    private var syncStatus: some View {
        HStack(spacing: 5) {
            syncIcon
            Text(store.syncLine)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(WatchPalette.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchPalette.surface, in: Capsule())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: store.queueCount)
    }

    @ViewBuilder
    private var syncIcon: some View {
        let icon = Image(systemName: store.queueCount == 0 ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
        if reduceMotion {
            icon
        } else {
            icon.symbolEffect(.pulse, options: .repeat(2), value: store.queueCount)
        }
    }

    private func tile(
        _ title: String,
        subtitle: String,
        symbol: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: symbol)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(WatchPalette.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(8)
            .background(WatchPalette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

enum WatchHomeRoute: Hashable {
    case home
    case mood
    case speak
    case record
    case recent

    init?(url: URL) {
        guard url.scheme == "offrecordwatch" else { return nil }
        switch url.host {
        case "home": self = .home
        case "mood": self = .mood
        case "speak": self = .speak
        case "record": self = .record
        case "recent": self = .recent
        default: self = .home
        }
    }

    static func sourceSurface(from url: URL) -> WatchCaptureSourceSurface {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawSource = components.queryItems?.first(where: { $0.name == "source" })?.value,
              let source = WatchCaptureSourceSurface(rawValue: rawSource) else {
            return url.host == "home" ? .complication : .app
        }
        return source
    }
}

struct WatchMoodDialView: View {
    @ObservedObject var store: WatchCaptureStore
    let source: WatchCaptureSourceSurface
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var crownFocused: Bool
    @State private var index = 4.0
    @State private var saved = false
    @State private var isSaving = false

    private var selectedMood: WatchMoodValue {
        WatchMoodValue.dialOrder[min(max(Int(index.rounded()), 0), WatchMoodValue.dialOrder.count - 1)]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [selectedMood.color.opacity(0.34), WatchPalette.ink],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 7) {
                Text(selectedMood.sentence)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WatchPalette.secondary)
                    .contentTransition(.opacity)

                ZStack {
                    Image(selectedMood.glowAssetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 130, height: 100)
                        .opacity(0.36)
                        .accessibilityHidden(true)

                    Image(selectedMood.largeAssetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: saved ? 82 : 76, height: saved ? 82 : 76)
                        .accessibilityLabel(selectedMood.displayName)

                    if saved {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title.weight(.heavy))
                            .foregroundStyle(.white, selectedMood.color)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.72), value: selectedMood)
                .animation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.66), value: saved)

                moodArc

                Text(selectedMood.supportiveCopy)
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Button {
                    guard !isSaving, !saved else { return }
                    isSaving = true
                    store.saveMood(selectedMood, source: source)
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        dismiss()
                    }
                } label: {
                    Label(saved ? "Saved" : "Save", systemImage: saved ? "checkmark.circle.fill" : "heart.circle.fill")
                }
                .tint(selectedMood.color)
                .disabled(isSaving || saved)
            }
            .padding(.horizontal, 8)
        }
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation(
            $index,
            from: 0,
            through: Double(WatchMoodValue.dialOrder.count - 1),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear { crownFocused = true }
        .onChange(of: index) { _, _ in WatchHaptics.selection() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mood dial")
        .accessibilityValue(selectedMood.displayName)
        .accessibilityHint("Turn the Digital Crown to choose a mood, then save.")
    }

    private var moodArc: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 4), spacing: 4) {
            ForEach(Array(WatchMoodValue.dialOrder.enumerated()), id: \.element) { moodIndex, mood in
                Button {
                    index = Double(moodIndex)
                } label: {
                    Image(mood.faceAssetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: mood == selectedMood ? 26 : 21, height: mood == selectedMood ? 26 : 21)
                        .frame(width: 34, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(mood == selectedMood ? mood.color.opacity(0.36) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mood.displayName)
            }
        }
        .frame(minHeight: 64)
    }
}

struct WatchSpeakCaptureView: View {
    @ObservedObject var store: WatchCaptureStore
    let source: WatchCaptureSourceSurface
    @Environment(\.dismiss) private var dismiss
    @FocusState private var textFocused: Bool
    @State private var text = ""
    @State private var saved = false
    @State private var isSaving = false
    @State private var isListening = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isListening ? "Listening" : "Speak")
                .font(.headline.weight(.heavy))

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(isListening ? "Two lines is enough." : "Tap Start and use dictation.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WatchPalette.secondary)
            } else {
                Text(WatchSpeechTruthState.transcriptOnWatchNow.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WatchPalette.secondary)
            }

            TextField("Tap to dictate", text: $text, axis: .vertical)
                .focused($textFocused)
                .lineLimit(2...2)
                .textInputAutocapitalization(.sentences)
                .padding(8)
                .background(WatchPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(previewText)
                .font(.caption)
                .foregroundStyle(WatchPalette.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                .padding(8)
                .background(WatchPalette.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 7) {
                Button(isListening ? "Stop" : "Start") {
                    isListening.toggle()
                    textFocused = isListening
                    WatchHaptics.selection()
                }
                    .buttonStyle(.borderless)
                Button(saved ? "Saved" : "Save") {
                    guard !isSaving, !saved else { return }
                    isSaving = true
                    store.saveSpeakText(text, source: source)
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        dismiss()
                    }
                }
                .disabled(isSaving || saved || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            NavigationLink {
                WatchRecordCaptureView(store: store, source: source)
            } label: {
                Label("Record instead", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            isListening = true
            textFocused = true
        }
    }

    private var previewText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return isListening ? "Listening privately..." : "No transcript yet."
        }
        return String(trimmed.prefix(120))
    }
}

struct WatchRecordCaptureView: View {
    @ObservedObject var store: WatchCaptureStore
    let source: WatchCaptureSourceSurface
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = WatchAudioRecorder()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var saved = false
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 9) {
            Text("Raw voice note")
                .font(.headline.weight(.heavy))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(WatchSpeechTruthState.audioOnly.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WatchPalette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                Circle()
                    .fill(recorder.isRecording ? WatchPalette.peach.opacity(recorder.isPaused ? 0.12 : 0.24) : WatchPalette.surface)
                    .frame(width: 88, height: 88)
                VStack(spacing: 2) {
                    Image(systemName: recorder.isPaused ? "pause.circle.fill" : (recorder.isRecording ? "record.circle.fill" : "mic.fill"))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(WatchPalette.peach)
                    Text(format(recorder.currentTime))
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
            }
            .scaleEffect(recorder.isRecording && !recorder.isPaused && !reduceMotion ? 1.04 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: recorder.isRecording && !recorder.isPaused)

            waveform

            if let message = recorder.errorMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if recorder.didReachSoftLimit {
                Text("Finish soon to keep this light.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text("Saved on watch first")
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.secondary)
            }

            if recorder.isRecording {
                HStack(spacing: 7) {
                    Button {
                        recorder.isPaused ? recorder.resume() : recorder.pause()
                    } label: {
                        Label(recorder.isPaused ? "Resume" : "Pause", systemImage: recorder.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        finishRecording()
                    } label: {
                        Label(saved ? "Saved" : "Finish", systemImage: saved ? "checkmark.circle.fill" : "stop.fill")
                    }
                    .tint(WatchPalette.peach)
                    .disabled(isSaving || saved)
                }
            } else {
                Button {
                    guard !isSaving, !saved else { return }
                    recorder.start()
                } label: {
                    Label(saved ? "Saved" : "Record", systemImage: saved ? "checkmark.circle.fill" : "record.circle")
                }
                .tint(WatchPalette.peach)
                .disabled(isSaving || saved)
            }
        }
        .padding(.horizontal, 8)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    recorder.cancel()
                    dismiss()
                }
            }
        }
        .onAppear {
            recorder.onHardLimitReached = { result in
                guard !isSaving, !saved else { return }
                isSaving = true
                store.saveAudio(fileURL: result.url, duration: result.duration, source: source)
                saved = true
                dismiss()
            }
        }
        .onDisappear {
            if recorder.isRecording && !saved {
                recorder.cancel()
            }
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<9, id: \.self) { offset in
                Capsule()
                    .fill(WatchPalette.peach.opacity(0.82))
                    .frame(width: 4, height: recorder.isPaused ? 8 : max(6, CGFloat(recorder.level) * CGFloat((offset % 4) + 1) * 9))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: recorder.level)
            }
        }
        .frame(height: 34)
        .accessibilityHidden(true)
    }

    private func finishRecording() {
        guard !isSaving, !saved else { return }
        if let result = recorder.stop() {
            isSaving = true
            store.saveAudio(fileURL: result.url, duration: result.duration, source: source)
            saved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                dismiss()
            }
        }
    }

    private func format(_ time: TimeInterval) -> String {
        let total = Int(time)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

struct WatchRecentCapturesView: View {
    @ObservedObject var store: WatchCaptureStore

    var body: some View {
        List {
            Section {
                ForEach(store.captures) { item in
                    HStack(spacing: 8) {
                        Image(systemName: symbol(for: item.envelope.kind))
                            .foregroundStyle(color(for: item.syncState))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.preview(for: item))
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(item.statusText)
                                .font(.caption2)
                                .foregroundStyle(WatchPalette.secondary)
                        }
                    }
                    .accessibilityLabel("\(item.title), \(item.statusText)")
                }
            } header: {
                Text("Recent")
            }
        }
        .overlay {
            if store.captures.isEmpty {
                ContentUnavailableView("Nothing held", systemImage: "checkmark.circle", description: Text("Quick captures will appear here until they are on your iPhone."))
            }
        }
    }

    private func symbol(for kind: WatchCaptureKind) -> String {
        switch kind {
        case .mood: return "face.smiling"
        case .speak: return "quote.bubble"
        case .audio: return "waveform"
        }
    }

    private func color(for state: WatchSyncState) -> Color {
        switch state {
        case .synced: return WatchPalette.sage
        case .failed: return .orange
        case .sending: return WatchPalette.lavender
        default: return WatchPalette.secondary
        }
    }
}
