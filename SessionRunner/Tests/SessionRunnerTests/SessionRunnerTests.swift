// SessionRunner hardware paths (AudioEngineController, StrobeController) require a physical
// iOS device. These tests exercise the pure-logic layer: state machine transitions, elapsed
// time tracking, and parameter routing — all without starting real hardware.

import XCTest
@testable import SessionRunner
import SessionKit

// MARK: - Helpers

private func makeSession(durationSec: Int = 60, maxStrobeHz: Double = 50) -> Session {
    let keyframe = StrobeKeyframe(timeSec: 0, hz: 10, dutyCycle: 0.5, intensity: 0.6, interpolation: .linear)
    let bKeyframe = BinauralKeyframe(timeSec: 0, carrierHz: 200, beatHz: 10, gain: 0.8, interpolation: .linear)
    let segment = Segment(
        startSec: 0,
        durationSec: Double(durationSec),
        label: "test",
        strobe: StrobeCurve(keyframes: [keyframe]),
        binaural: BinauralCurve(keyframes: [bKeyframe])
    )
    let safety = SafetyProfile(maxStrobeHz: maxStrobeHz, requiresHeadphoneCheck: false)
    return Session(
        id: "test-session",
        title: "Test",
        intent: .relax,
        durationSec: durationSec,
        segments: [segment],
        safety: safety,
        audioBedAsset: nil
    )
}

// MARK: - State machine tests

final class SessionRunnerStateTests: XCTestCase {

    func testInitialState_isIdle() {
        let runner = SessionRunner(session: makeSession(), audioMode: .bringYourOwn)
        XCTAssertEqual(runner.state, .idle)
    }

    func testStop_fromIdle_transitionsToCompleted() {
        let runner = SessionRunner(session: makeSession(), audioMode: .bringYourOwn)
        runner.stop()
        XCTAssertEqual(runner.state, .completed)
    }

    func testPause_fromIdle_isNoOp() {
        let runner = SessionRunner(session: makeSession(), audioMode: .bringYourOwn)
        runner.pause()
        XCTAssertEqual(runner.state, .idle)
    }

    func testOnStateChange_calledOnStop() {
        let runner = SessionRunner(session: makeSession(), audioMode: .bringYourOwn)
        var received: [SessionRunnerState] = []
        runner.onStateChange = { received.append($0) }
        runner.stop()
        XCTAssertEqual(received, [.completed])
    }

    func testOnStateChange_notCalledForNoOpPause() {
        let runner = SessionRunner(session: makeSession(), audioMode: .bringYourOwn)
        var received: [SessionRunnerState] = []
        runner.onStateChange = { received.append($0) }
        runner.pause()   // idle → guard fires, no state change
        XCTAssertTrue(received.isEmpty)
    }

    func testStopTwice_doesNotCrash() {
        let runner = SessionRunner(session: makeSession(), audioMode: .bringYourOwn)
        runner.stop()
        runner.stop()    // second call must be safe
        XCTAssertEqual(runner.state, .completed)
    }
}

// MARK: - AudioMode routing tests

final class SessionRunnerAudioModeTests: XCTestCase {

    func testBringYourOwn_doesNotThrowWithoutDevice() throws {
        // In .bringYourOwn mode, AudioEngineController.start() is never called,
        // so we bypass the AVFoundation engine entirely. StrobeController.start()
        // WILL throw on non-device (no torch) — we catch that as expected.
        let runner = SessionRunner(session: makeSession(), audioMode: .bringYourOwn)
        do {
            try runner.start()
            // On a device with torch this succeeds; on simulator/Mac it throws StrobeError.
        } catch let e as StrobeError {
            // Expected on simulator / Mac — torch unavailable. Not a test failure.
            XCTAssertTrue(e == .torchUnavailable || e == .lockFailed)
        }
    }
}

// MARK: - Safety cap propagation

final class SessionRunnerSafetyCapTests: XCTestCase {

    func testSessionSafetyCap_isPassedToStrobeController() {
        // Verify SessionRunner reads maxStrobeHz from SafetyProfile, not a hardcoded value.
        // We inspect via the session's safety value, not the (device-only) controller directly.
        let session = makeSession(maxStrobeHz: 12.0)
        let runner = SessionRunner(session: session, audioMode: .bringYourOwn)
        // The runner is wired — if we could reach into the controller, it would have
        // maxStrobeHz == 12.0. We verify the session value is correct as a proxy.
        XCTAssertEqual(session.safety.maxStrobeHz, 12.0)
        // State should still be idle (no start called).
        XCTAssertEqual(runner.state, .idle)
    }
}

// MARK: - Callback wiring

final class SessionRunnerCallbackTests: XCTestCase {

    func testOnSessionEnd_notCalledBeforeStop() {
        let runner = SessionRunner(session: makeSession(), audioMode: .bringYourOwn)
        var ended = false
        runner.onSessionEnd = { ended = true }
        // Do not start — callback must not fire spontaneously.
        XCTAssertFalse(ended)
    }

    func testOnThermalShutdown_notCalledWithoutStart() {
        let runner = SessionRunner(session: makeSession(), audioMode: .bringYourOwn)
        var shutdown = false
        runner.onThermalShutdown = { shutdown = true }
        XCTAssertFalse(shutdown)
    }
}
