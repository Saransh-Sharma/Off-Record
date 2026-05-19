//
//  AudioPlayerView.swift
//  OffRecord
//
//  Enhanced audio player with progress bar, time display, and speed control.
//

import SwiftUI
import AVFoundation

// MARK: - Audio Playback Controller

final class AudioPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    static let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    func load(url: URL) throws {
        stop()
        let player = try AVAudioPlayer(contentsOf: url)
        player.enableRate = true
        player.delegate = self
        player.prepareToPlay()
        self.audioPlayer = player
        self.duration = player.duration
        self.currentTime = 0
    }

    func togglePlayback() {
        guard let player = audioPlayer else { return }
        if isPlaying {
            player.pause()
            stopTimer()
        } else {
            player.rate = playbackRate
            player.play()
            startTimer()
        }
        isPlaying = !isPlaying
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    func setSpeed(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            audioPlayer?.rate = rate
        }
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let player = self.audioPlayer else { return }
            self.currentTime = player.currentTime
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentTime = 0
            self.stopTimer()
        }
    }

    func stop() {
        stopTimer()
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    deinit {
        stop()
    }
}

// MARK: - Audio Player View

struct AudioPlayerView: View {
    let audioURL: URL

    @StateObject private var controller = AudioPlaybackController()
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 12) {
            // Play/Pause + Slider + Time
            HStack(spacing: 12) {
                Button {
                    controller.togglePlayback()
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(OffRecordReadableTintStyle.journal.foreground)
                        .frame(width: 44, height: 44)
                        .offRecordGlassControl(
                            tint: OffRecordReadableTintStyle.journal.tint,
                            in: Circle(),
                            fallbackFill: OffRecordReadableTintStyle.journal.fill,
                            border: OffRecordReadableTintStyle.journal.border
                        )
                }
                .buttonStyle(.plain)

                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { controller.currentTime },
                            set: { controller.seek(to: $0) }
                        ),
                        in: 0...max(0.01, controller.duration)
                    )
                    .tint(OffRecordColor.brandAqua)

                    HStack {
                        Text(formatTime(controller.currentTime))
                            .font(OffRecordTypography.metadata.monospacedDigit())
                            .foregroundColor(OffRecordColor.textSecondary)
                        Spacer()
                        Text(formatTime(controller.duration))
                            .font(OffRecordTypography.metadata.monospacedDigit())
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                }
            }

            // Speed selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("Speed")
                        .font(OffRecordTypography.annotation)
                        .foregroundColor(OffRecordColor.textSecondary)

                    ForEach(AudioPlaybackController.speedOptions, id: \.self) { speed in
                        Button {
                            controller.setSpeed(speed)
                            HapticManager.shared.selectionChanged()
                        } label: {
                            Text(speedLabel(speed))
                                .font(controller.playbackRate == speed ? OffRecordTypography.labelSmall : OffRecordTypography.metadata)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .foregroundColor(controller.playbackRate == speed ? OffRecordReadableTintStyle.growth.foreground : OffRecordColor.textSecondary)
                                .offRecordGlassControl(
                                    tint: controller.playbackRate == speed ? OffRecordReadableTintStyle.growth.tint : nil,
                                    in: Capsule(),
                                    fallbackFill: controller.playbackRate == speed ? OffRecordReadableTintStyle.growth.fill : OffRecordReadableTintStyle.neutral.fill,
                                    border: controller.playbackRate == speed ? OffRecordReadableTintStyle.growth.border : OffRecordReadableTintStyle.neutral.border
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .offRecordContentCard(cornerRadius: 12)
        .onAppear {
            do {
                try controller.load(url: audioURL)
            } catch {
                loadError = "Unable to load audio."
            }
        }
        .onDisappear {
            controller.stop()
        }
        .overlay {
            if let error = loadError {
                Text(error)
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textCoral)
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func speedLabel(_ speed: Float) -> String {
        if speed == 1.0 { return "1x" }
        if speed == floor(speed) { return "\(Int(speed))x" }
        return String(format: "%.1fx", speed).replacingOccurrences(of: ".0x", with: "x")
    }
}
