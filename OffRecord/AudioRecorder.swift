//
//  AudioRecorder.swift
//  OffRecord
//
//  Handles audio recording for voice diary entries.
//  Recordings are stored locally in the app's sandboxed container.
//
//  Privacy: Audio files never leave the device unless explicitly exported by user.
//

import Foundation
import AVFoundation
import os.log

private let recorderLogger = Logger(subsystem: "com.singularity.offrecord", category: "AudioRecorder")

/// Manages audio recording for voice diary entries.
/// All recordings are stored in the app's protected Application Support directory.
///
/// Recording runs on an `AVAudioEngine` input tap so the same microphone stream
/// can be written to an AAC file, drive a real waveform, and feed live
/// transcription. If the engine cannot start, it falls back to `AVAudioRecorder`.
final class AudioRecorder: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var isRecording = false
    @Published private(set) var isPaused = false
    @Published var currentTime: TimeInterval = 0
    @Published var level: Float = 0  // 0...1 normalized audio level
    /// Recent normalized levels, oldest first, sampled about 20 times a second.
    @Published private(set) var levelHistory: [Float] = []
    /// Set when the system interrupted recording (a call, Siri, another app).
    @Published private(set) var wasInterrupted = false

    static let levelHistoryCapacity = 72

    /// Receives raw microphone buffers on the audio thread while recording (not while paused).
    /// Only delivered on the engine path.
    var bufferHandler: ((AVAudioPCMBuffer) -> Void)? {
        get { stateLock.withLock { _bufferHandler } }
        set { stateLock.withLock { _bufferHandler = newValue } }
    }
    private var _bufferHandler: ((AVAudioPCMBuffer) -> Void)?

    /// Whether the active recording streams buffers to `bufferHandler`.
    private(set) var supportsBufferStreaming = false

    // MARK: - Private Properties

    private var engine: AVAudioEngine?
    // Read on the audio thread; guarded by `stateLock`.
    private var outputFile: AVAudioFile?
    private var fileConverter: AVAudioConverter?
    private var fallbackRecorder: AVAudioRecorder?
    private var outputURL: URL?
    private var timer: Timer?
    private var audioSessionPrepared = false
    private var interruptionObserver: NSObjectProtocol?

    private let stateLock = NSLock()
    private var framesWritten: AVAudioFramePosition = 0
    private var sampleRate: Double = 44_100
    private var latestTapLevel: Float = 0
    private var tapPaused = false

    private let fallbackSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    func prepareForFirstUse() {
        #if os(iOS)
        DispatchQueue.global(qos: .utility).async {
            let token = PerformanceSignposts.begin("AudioRecorderPrewarm")
            _ = try? Self.recordingsDirectory()
            PerformanceSignposts.end(token)
        }
        #endif
    }

    // MARK: - Recording

    func startRecording() throws {
        #if os(iOS)
        let token = PerformanceSignposts.begin("AudioRecorderStart")
        defer { PerformanceSignposts.end(token) }

        try prepareAudioSessionIfNeeded()
        let url = try Self.newRecordingURL()
        outputURL = url

        resetMeters()
        do {
            try startEngineRecording(to: url)
            supportsBufferStreaming = true
        } catch {
            recorderLogger.error("Engine recording failed, falling back to AVAudioRecorder: \(error.localizedDescription, privacy: .public)")
            teardownEngine()
            try startFallbackRecording(to: url)
            supportsBufferStreaming = false
        }

        isRecording = true
        isPaused = false
        wasInterrupted = false
        Self.activeRecording = true
        observeInterruptions()
        startMeterTimer()
        #else
        throw NSError(domain: "AudioRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Recording is only available on iOS."])
        #endif
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        if let engine {
            stateLock.withLock { tapPaused = true }
            engine.pause()
        } else {
            fallbackRecorder?.pause()
        }
        isPaused = true
        level = 0
    }

    func resume() throws {
        guard isRecording, isPaused else { return }
        #if os(iOS)
        try AVAudioSession.sharedInstance().setActive(true)
        #endif
        if let engine {
            try engine.start()
            stateLock.withLock { tapPaused = false }
        } else {
            fallbackRecorder?.record()
        }
        isPaused = false
        wasInterrupted = false
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard isRecording, let url = outputURL else { return nil }
        let duration = recordedDuration()

        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        fallbackRecorder?.stop()

        // Releasing the file finalizes the AAC container.
        stateLock.withLock {
            outputFile = nil
            fileConverter = nil
            _bufferHandler = nil
        }
        self.engine = nil
        fallbackRecorder = nil
        outputURL = nil

        timer?.invalidate()
        timer = nil
        removeInterruptionObserver()
        isRecording = false
        isPaused = false
        Self.activeRecording = false
        level = 0
        return (url, duration)
    }

    /// Stops recording and deletes the file.
    func discardRecording() {
        guard let result = stopRecording() else { return }
        try? FileManager.default.removeItem(at: result.url)
    }

    deinit {
        timer?.invalidate()
        engine?.stop()
        fallbackRecorder?.stop()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        Self.activeRecording = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Engine path

    #if os(iOS)
    private func startEngineRecording(to url: URL) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "AudioRecorder", code: -2, userInfo: [NSLocalizedDescriptionKey: "No audio input available."])
        }

        let fileSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: fileSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        var converter: AVAudioConverter?
        if inputFormat != file.processingFormat {
            converter = AVAudioConverter(from: inputFormat, to: file.processingFormat)
            converter?.downmix = true
        }

        stateLock.withLock {
            framesWritten = 0
            sampleRate = inputFormat.sampleRate
            tapPaused = false
            outputFile = file
            fileConverter = converter
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.handleTap(buffer)
        }

        self.engine = engine
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    private func handleTap(_ buffer: AVAudioPCMBuffer) {
        let (paused, file, converter, handler) = stateLock.withLock {
            (tapPaused, outputFile, fileConverter, _bufferHandler)
        }
        guard !paused else { return }

        if let file {
            do {
                if let converter {
                    if let converted = convert(buffer, with: converter, to: file.processingFormat) {
                        try file.write(from: converted)
                    }
                } else {
                    try file.write(from: buffer)
                }
            } catch {
                recorderLogger.error("Failed writing audio buffer: \(error.localizedDescription, privacy: .public)")
            }
        }

        let level = Self.normalizedLevel(of: buffer)
        stateLock.withLock {
            framesWritten += AVAudioFramePosition(buffer.frameLength)
            latestTapLevel = level
        }
        handler?(buffer)
    }

    private func convert(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil else { return nil }
        return output
    }

    private static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        let decibels = 20 * log10(max(rms, 0.000_001))
        return max(0, min(1, (decibels + 55) / 55))
    }

    private func teardownEngine() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        stateLock.withLock {
            outputFile = nil
            fileConverter = nil
        }
    }

    // MARK: - Fallback path

    private func startFallbackRecording(to url: URL) throws {
        let recorder = try AVAudioRecorder(url: url, settings: fallbackSettings)
        recorder.isMeteringEnabled = true
        recorder.delegate = self
        guard recorder.record() else {
            throw NSError(domain: "AudioRecorder", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unable to start recording."])
        }
        fallbackRecorder = recorder
    }

    private func prepareAudioSessionIfNeeded() throws {
        let token = PerformanceSignposts.begin("AudioSessionPrepare")
        defer { PerformanceSignposts.end(token) }

        let session = AVAudioSession.sharedInstance()
        if !audioSessionPrepared || session.category != .playAndRecord {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            audioSessionPrepared = true
        }
        try session.setActive(true)
    }

    // MARK: - Interruptions

    private func observeInterruptions() {
        removeInterruptionObserver()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
            // Keep what was captured; the person chooses when to resume.
            self.pause()
            self.wasInterrupted = true
        }
    }
    #endif

    private func removeInterruptionObserver() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
    }

    // MARK: - Metering

    private func resetMeters() {
        currentTime = 0
        level = 0
        levelHistory = []
        stateLock.withLock {
            framesWritten = 0
            latestTapLevel = 0
        }
    }

    private func startMeterTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.sampleMeters()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sampleMeters() {
        guard isRecording, !isPaused else { return }
        let sampled: Float
        if let fallbackRecorder {
            fallbackRecorder.updateMeters()
            let power = fallbackRecorder.averagePower(forChannel: 0)
            sampled = max(0, min(1, (power + 55) / 55))
        } else {
            sampled = stateLock.withLock { latestTapLevel }
        }
        // Light smoothing keeps the waveform lively without jitter.
        level = level * 0.35 + sampled * 0.65
        var history = levelHistory
        history.append(level)
        if history.count > Self.levelHistoryCapacity {
            history.removeFirst(history.count - Self.levelHistoryCapacity)
        }
        levelHistory = history
        currentTime = recordedDuration()
    }

    /// Fills the meters with a natural-looking speech pattern for App Store screenshots.
    func showScreenshotSample(duration: TimeInterval) {
        currentTime = duration
        levelHistory = (0..<Self.levelHistoryCapacity).map { index in
            let t = Double(index)
            let phrase = 0.6 + 0.35 * sin(t / 5) * sin(t / 11 + 1)
            let syllable = 0.45 + 0.55 * abs(sin(t * 1.7))
            return Float(max(0.08, min(1, phrase * syllable)))
        }
        level = levelHistory.last ?? 0
    }

    private func recordedDuration() -> TimeInterval {
        if let fallbackRecorder {
            return fallbackRecorder.currentTime
        }
        return stateLock.withLock {
            sampleRate > 0 ? Double(framesWritten) / sampleRate : 0
        }
    }

    // MARK: - File Management

    /// Returns the directory for storing recordings.
    /// Located in Application Support, which is protected by iOS sandbox.
    private static func recordingsDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "AudioRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot access Application Support directory."])
        }
        let directory = base.appendingPathComponent("Recordings", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        return directory
    }

    /// Generates a unique filename for a new recording.
    /// Uses UUID to prevent filename collisions and avoid exposing metadata.
    private static func newRecordingURL() throws -> URL {
        let directory = try recordingsDirectory()
        let filename = UUID().uuidString + ".m4a"
        return directory.appendingPathComponent(filename)
    }

    /// Whether a recording is currently in progress (shared flag for cleanup guard).
    private static var activeRecording = false

    /// Cleans up old recording files that are no longer referenced.
    /// Called periodically to manage storage.
    static func cleanupOrphanedRecordings(keepURLs: Set<URL>) {
        guard !activeRecording else { return }
        do {
            let directory = try recordingsDirectory()
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in files where !keepURLs.contains(file) {
                try? FileManager.default.removeItem(at: file)
            }
        } catch {
            // Silently fail - cleanup is not critical
        }
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {}
