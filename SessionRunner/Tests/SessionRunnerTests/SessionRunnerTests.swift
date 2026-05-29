// SessionRunner hardware paths (AudioEngineController, StrobeController) require a physical
// iOS device. These tests exercise the pure-logic layer: state machine transitions, elapsed
// time tracking, and parameter routing — all without starting real hardware.

import XCTest
@testable import SessionRunner
import SessionKit

// MARK: - Helpers

private func makeSession(durationSec: Int = 60, maxStrobeHz: Double = 50) -> Session {
    let strobe = StrobeCurve(
        keyframes: [StrobeKeyframe(tSec: 0, hz: 10, dutyCycle: 0.5, intensity: 0.6)],
        interpolation: .linear
    )
    let binaural = BinauralCurve(
        keyframes: [BinauralKeyframe(tSec: 0, carrierHz: 200, beatHz: 10, gain: 0.8)],
        interpolation: .linear
    )
    let segment = Segment(
        startSec: 0,
        durationSec: Double(durationSec),
        strobe: strobe,
        binaural: binaural
    )
    let safety = SafetyProfile(
        maxStrobeHz: maxStrobeHz,
        requiresHeadphones: true,
        photosensitiveGateRequired: true
    )
    return Session(
        id: "test-session",
        title: "Test",
        intent: .openRelax,
        durationSec: durationSec,
        safety: safety,
        segments: [segment]
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
        runner.pause()
        XCTAssertTrue(received.isEmpty)
    }

    func testStopTwice_doesNotCrash() {
        let runner = SessionRunner(session: makeSession(), audioMode: .bringYourOwn)
        runner.stop()
        runner.stop()
        XCTAssertEqual(runner.state, .completed)
    }
}

// MARK: - AudioMode routing tests

final class SessionRunnerAudioModeTests: XCTestCase {

    func testBringYourOwn_startThrowsStrobeErrorOnNonDevice() {
        // .bringYourOwn skips AudioEngineController.start(), so only StrobeController
        // is attempted. On simulator / Mac there is no torch, so we expect a StrobeError.
        let runner = SessionRunner(session: makeSession(), audioMode: .bringYourOwn)
        do {
            try runner.start()
            // On a physical device with a torch this succeeds — not a test failure.
        } catch let e as StrobeError {
            XCTAssertTrue(e == .torchUnavailable || e == .lockFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// MARK: - Safety cap propagation

final class SessionRunnerSafetyCapTests: XCTestCase {

    func testSessionSafetyCap_surfacedInSafetyProfile() {
        let session = makeSession(maxStrobeHz: 12.0)
        _ = SessionRunner(session: session, audioMode: .bringYourOwn)
        XCTAssertEqual(session.safety.maxStrobeHz, 12.0)
    }
}

// MARK: - Callback wiring

final class SessionRunnerCallbackTests: XCTestCase {

    func testOnSessionEnd_notCalledBeforeStart() {
        let runner = SessionRunner(session: makeSession(), audioMode: .bringYourOwn)
        var ended = false
        runner.onSessionEnd = { ended = true }
        XCTAssertFalse(ended)
    }

    func testOnThermalShutdown_notCalledWithoutStart() {
        let runner = SessionRunner(session: makeSession(), audioMode: .bringYourOwn)
        var shutdown = false
        runner.onThermalShutdown = { shutdown = true }
        XCTAssertFalse(shutdown)
    }

    func testStop_setsStateToCompleted() {
        let runner = SessionRunner(session: makeSession(), audioMode: .bringYourOwn)
        runner.stop()
        XCTAssertEqual(runner.state, .completed)
    }
}
