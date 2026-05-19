import Foundation
import MetricKit
import os.log

private let metricsLogger = Logger(subsystem: "com.singularity.offrecord", category: "MetricKit")

final class AppMetricsSubscriber: NSObject, MXMetricManagerSubscriber {
    static let shared = AppMetricsSubscriber()

    private var isRegistered = false

    private override init() {
        super.init()
    }

    func start() {
        guard !isRegistered else { return }
        isRegistered = true
        MXMetricManager.shared.add(self)
    }

    deinit {
        if isRegistered {
            MXMetricManager.shared.remove(self)
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            if let memory = payload.memoryMetrics {
                let peakMB = memory.peakMemoryUsage.converted(to: .megabytes).value
                let suspendedDescription = String(describing: memory.averageSuspendedMemory)
                metricsLogger.info("MetricKit memory peakMB=\(peakMB, privacy: .public) averageSuspended=\(suspendedDescription, privacy: .public)")
            }

            if #available(iOS 14.0, *), let exits = payload.applicationExitMetrics {
                logBackgroundExitData(exits.backgroundExitData)
                logForegroundExitData(exits.foregroundExitData)
            }
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        metricsLogger.info("MetricKit diagnostics payloads=\(payloads.count, privacy: .public)")
    }

    @available(iOS 14.0, *)
    private func logBackgroundExitData(_ data: MXBackgroundExitData) {
        metricsLogger.info(
            "MetricKit exits scope=background normal=\(data.cumulativeNormalAppExitCount, privacy: .public) memoryLimit=\(data.cumulativeMemoryResourceLimitExitCount, privacy: .public) memoryPressure=\(data.cumulativeMemoryPressureExitCount, privacy: .public) watchdog=\(data.cumulativeAppWatchdogExitCount, privacy: .public) lockedFile=\(data.cumulativeSuspendedWithLockedFileExitCount, privacy: .public) cpuLimit=\(data.cumulativeCPUResourceLimitExitCount, privacy: .public) taskTimeout=\(data.cumulativeBackgroundTaskAssertionTimeoutExitCount, privacy: .public)"
        )
    }

    @available(iOS 14.0, *)
    private func logForegroundExitData(_ data: MXForegroundExitData) {
        metricsLogger.info(
            "MetricKit exits scope=foreground normal=\(data.cumulativeNormalAppExitCount, privacy: .public) memoryLimit=\(data.cumulativeMemoryResourceLimitExitCount, privacy: .public) watchdog=\(data.cumulativeAppWatchdogExitCount, privacy: .public) badAccess=\(data.cumulativeBadAccessExitCount, privacy: .public) illegalInstruction=\(data.cumulativeIllegalInstructionExitCount, privacy: .public) abnormal=\(data.cumulativeAbnormalExitCount, privacy: .public)"
        )
    }
}
