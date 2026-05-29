import Foundation
import UIKit
import SessionKit
import SessionRunner

final class AppState: ObservableObject {

    // MARK: - Persisted

    @Published var hasAcknowledgedSafetyGate: Bool

    // MARK: - Session state

    @Published var audioMode: AudioMode = .engine
    @Published var runnerState: SessionRunnerState = .idle
    @Published var currentSession: Session?

    // MARK: - Data

    let sessionStore = SessionStore()

    // MARK: - Private

    private var runner: SessionRunner?
    private static let gateKey = "com.fablesignal.safetyGateAcknowledged"

    // MARK: - Init

    init() {
        self.hasAcknowledgedSafetyGate = UserDefaults.standard.bool(forKey: Self.gateKey)
    }

    // MARK: - Gate

    func acknowledgeGate() {
        hasAcknowledgedSafetyGate = true
        UserDefaults.standard.set(true, forKey: Self.gateKey)
    }

    func resetGateAcknowledgment() {
        UserDefaults.standard.removeObject(forKey: Self.gateKey)
        hasAcknowledgedSafetyGate = false
    }

    // MARK: - Session lifecycle

    /// Start `session` using the current `audioMode`. Throws `StrobeError` or AVFoundation errors.
    func startSession(_ session: Session) throws {
        runner?.stop()
        runner = nil
        runnerState = .idle

        let r = SessionRunner(session: session, audioMode: audioMode)
        r.onStateChange = { [weak self] state in self?.runnerState = state }
        r.onSessionEnd = { [weak self] in
            self?.runnerState = .completed
            UIApplication.shared.isIdleTimerDisabled = false
        }
        r.onThermalShutdown = { [weak self] in
            self?.runnerState = .completed
            UIApplication.shared.isIdleTimerDisabled = false
        }

        do {
            try r.start()
        } catch {
            r.stop()
            throw error
        }
        runner = r
        currentSession = session
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func pauseSession() {
        runner?.pause()
    }

    func resumeSession() throws {
        try runner?.resume()
    }

    func stopSession() {
        runner?.stop()
        runner = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
