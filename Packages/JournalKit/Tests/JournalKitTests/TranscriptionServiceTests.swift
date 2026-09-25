import Foundation
import Testing
@testable import TranscriptionKit

@Suite(.serialized)
struct TranscriptionServiceTests {

    // MARK: - Helpers

    private struct MockEngine: TranscriptionEngine {
        let kind: TranscriptionEngineKind
        var text: String = "hello world."
        var error: TranscriptionError?
        var delay: TimeInterval = 0

        func transcribeFile(at url: URL) async throws -> FileTranscriptionResult {
            if delay > 0 {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            if let error {
                throw error
            }
            return FileTranscriptionResult(
                text: text,
                engine: kind,
                locale: Locale(identifier: "en_US"),
                processingDuration: delay
            )
        }
    }

    private let dummyURL = URL(fileURLWithPath: "/dev/null")

    // MARK: - Post-processing

    @Test func terminalPunctuationAppendedWhenMissing() {
        #expect(TranscriptionPostProcessing.appendingTerminalPunctuation(to: "hello") == "hello.")
        #expect(TranscriptionPostProcessing.appendingTerminalPunctuation(to: "hello.") == "hello.")
        #expect(TranscriptionPostProcessing.appendingTerminalPunctuation(to: "hello?") == "hello?")
        #expect(TranscriptionPostProcessing.appendingTerminalPunctuation(to: "hello!") == "hello!")
        #expect(TranscriptionPostProcessing.appendingTerminalPunctuation(to: "") == "")
    }

    // MARK: - Consent gate

    @Test func transcribeThrowsWithoutConsent() async {
        let service = TranscriptionService(
            consentProvider: { false },
            engineFactory: { MockEngine(kind: .speechTranscriber) }
        )
        do {
            _ = try await service.transcribe(from: dummyURL)
            Issue.record("Expected appleSpeechConsentRequired")
        } catch let error as TranscriptionError {
            guard case .appleSpeechConsentRequired = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Success path

    @Test func transcribeReturnsEngineResult() async throws {
        let service = TranscriptionService(engineFactory: { MockEngine(kind: .speechTranscriber, text: "note to self.") })
        let result = try await service.transcribe(from: dummyURL)
        #expect(result.text == "note to self.")
        #expect(result.engine == .speechTranscriber)
    }

    // MARK: - Job isolation

    @Test func concurrentJobsBothComplete() async throws {
        let service = TranscriptionService(engineFactory: { MockEngine(kind: .dictationTranscriber, text: "job done.", delay: 0.1) })
        async let first = service.transcribe(from: dummyURL)
        async let second = service.transcribe(from: dummyURL)
        let results = try await [first, second]
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.text == "job done." })
    }

    @Test func moreJobsThanConcurrencyLimitAllComplete() async throws {
        let service = TranscriptionService(engineFactory: { MockEngine(kind: .speechTranscriber, text: "queued.", delay: 0.05) })
        let results = try await withThrowingTaskGroup(of: FileTranscriptionResult.self) { group in
            for _ in 0..<5 {
                group.addTask { try await service.transcribe(from: dummyURL) }
            }
            var collected: [FileTranscriptionResult] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }
        #expect(results.count == 5)
    }

    // MARK: - Analyzer-only failure behavior

    @Test func modelInstallationFailurePropagatesWithoutAnotherSpeechStack() async {
        let service = TranscriptionService(
            engineFactory: { MockEngine(kind: .speechTranscriber, error: .modelNotInstalled) }
        )
        do {
            _ = try await service.transcribe(from: dummyURL)
            Issue.record("Expected modelNotInstalled")
        } catch let error as TranscriptionError {
            guard case .modelNotInstalled = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func analyzerFailurePropagates() async {
        let service = TranscriptionService(
            engineFactory: { MockEngine(kind: .speechTranscriber, error: .noFinalResult) }
        )
        do {
            _ = try await service.transcribe(from: dummyURL)
            Issue.record("Expected noFinalResult")
        } catch let error as TranscriptionError {
            guard case .noFinalResult = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func dictationAnalyzerResultIsReportedAccurately() async throws {
        let service = TranscriptionService(
            engineFactory: { MockEngine(kind: .dictationTranscriber, text: "dictated.") }
        )
        let result = try await service.transcribe(from: dummyURL)
        #expect(result.engine == .dictationTranscriber)
        #expect(result.text == "dictated.")
    }

    // MARK: - Timeout

    @Test func hangingEngineTimesOutInsteadOfHangingForever() async {
        let service = TranscriptionService(
            jobTimeout: 0.2,
            engineFactory: { MockEngine(kind: .speechTranscriber, delay: 30) }
        )
        do {
            _ = try await service.transcribe(from: dummyURL)
            Issue.record("Expected timeout")
        } catch let error as TranscriptionError {
            guard case .noFinalResult = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        } catch {
            // Task cancellation surfacing as CancellationError is also acceptable
        }
    }
}
