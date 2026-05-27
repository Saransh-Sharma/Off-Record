import AVFoundation
import Foundation
import os.log

private let watchAudioLogger = Logger(subsystem: "com.singularity.offrecord.watch", category: "AudioRecorder")

@MainActor
final class WatchAudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var level: Float = 0
    @Published private(set) var didReachSoftLimit = false
    @Published private(set) var didReachHardLimit = false
    @Published var errorMessage: String?

    var onHardLimitReached: (((url: URL, duration: TimeInterval)) -> Void)?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var interruptionObserver: NSObjectProtocol?
    private var isStarting = false

    static let softDurationLimit: TimeInterval = 5 * 60
    static let hardDurationLimit: TimeInterval = 10 * 60

    private let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 24_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
    ]

    override init() {
        super.init()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
            }
        }
    }

    deinit {
        timer?.invalidate()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        recorder?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func start() {
        guard !isStarting, !isRecording, recorder == nil else { return }
        isStarting = true
        errorMessage = nil
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard self.isStarting else { return }
                guard granted else {
                    self.isStarting = false
                    self.errorMessage = "Microphone access is off."
                    WatchHaptics.warning()
                    return
                }
                do {
                    try self.startRecording()
                    self.isStarting = false
                } catch {
                    self.isStarting = false
                    self.errorMessage = "Could not start recording."
                    watchAudioLogger.error("Watch recording start failed: \(error.localizedDescription, privacy: .public)")
                    WatchHaptics.error()
                }
            }
        }
    }

    func stop() -> (url: URL, duration: TimeInterval)? {
        guard let recorder else { return nil }
        let duration = recorder.currentTime
        let url = recorder.url
        recorder.stop()
        timer?.invalidate()
        timer = nil
        self.recorder = nil
        isStarting = false
        isRecording = false
        isPaused = false
        level = 0
        currentTime = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        WatchHaptics.stop()
        return (url, duration)
    }

    func pause() {
        guard isRecording, !isPaused, let recorder else { return }
        recorder.pause()
        isPaused = true
        level = 0
        WatchHaptics.selection()
    }

    func resume() {
        guard isRecording, isPaused, let recorder else { return }
        recorder.record()
        isPaused = false
        WatchHaptics.start()
    }

    func cancel() {
        guard let recorder else { return }
        let url = recorder.url
        recorder.stop()
        timer?.invalidate()
        timer = nil
        self.recorder = nil
        isStarting = false
        isRecording = false
        isPaused = false
        level = 0
        currentTime = 0
        try? FileManager.default.removeItem(at: url)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio)
        try session.setActive(true)

        let url = Self.recordingsDirectory().appendingPathComponent(UUID().uuidString + ".m4a")
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        let didStart = recorder.record()
        guard didStart else {
            try? FileManager.default.removeItem(at: url)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw NSError(
                domain: "WatchAudioRecorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "AVAudioRecorder did not start recording."]
            )
        }
        self.recorder = recorder
        isRecording = true
        isPaused = false
        currentTime = 0
        level = 0
        didReachSoftLimit = false
        didReachHardLimit = false
        WatchHaptics.start()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                guard !self.isPaused else {
                    self.level = 0
                    return
                }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                self.level = max(0, min(1, (power + 60) / 60))
                self.currentTime = recorder.currentTime
                if self.currentTime >= Self.softDurationLimit, !self.didReachSoftLimit {
                    self.didReachSoftLimit = true
                    WatchHaptics.warning()
                }
                if self.currentTime >= Self.hardDurationLimit, !self.didReachHardLimit {
                    self.didReachHardLimit = true
                    if let result = self.stop() {
                        self.onHardLimitReached?(result)
                    }
                }
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            if isRecording, !isPaused {
                pause()
                errorMessage = "Recording paused."
            }
        case .ended:
            errorMessage = "Tap Resume when ready."
        @unknown default:
            break
        }
    }

    static func recordingsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
