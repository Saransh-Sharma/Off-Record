import Foundation
import os.log
@preconcurrency import WatchConnectivity

private let watchConnectivityLogger = Logger(subsystem: "com.singularity.offrecord.watch", category: "Connectivity")

@MainActor
final class WatchConnectivityCoordinator: NSObject, ObservableObject {
    static let shared = WatchConnectivityCoordinator()

    @Published private(set) var isReachable = false
    @Published private(set) var activationState: WCSessionActivationState = .notActivated

    var onReceipt: ((WatchCaptureReceipt) -> Void)?

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func transfer(_ envelope: WatchCaptureEnvelope) {
        guard WCSession.isSupported() else { return }
        do {
            WCSession.default.transferUserInfo(try envelope.userInfoPayload())
        } catch {
            watchConnectivityLogger.warning("Could not encode watch metadata transfer: \(error.localizedDescription, privacy: .public)")
        }
    }

    func transferAudio(fileURL: URL, envelope: WatchCaptureEnvelope) {
        guard WCSession.isSupported() else { return }
        do {
            WCSession.default.transferFile(fileURL, metadata: try envelope.userInfoPayload())
        } catch {
            watchConnectivityLogger.warning("Could not encode watch audio transfer metadata: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func receive(_ userInfo: [String: Any]) {
        guard let receipt = try? WatchCaptureReceipt.decoded(from: userInfo) else { return }
        onReceipt?(receipt)
    }
}

extension WatchConnectivityCoordinator: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.activationState = activationState
            self.isReachable = reachable
        }
        if let error {
            watchConnectivityLogger.warning("Watch session activation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isReachable = reachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async {
            self.receive(userInfo)
        }
    }
}
