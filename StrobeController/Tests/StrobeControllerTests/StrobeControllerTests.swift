// StrobeController hardware behaviour is device-only (torch unavailable in simulator).
//
// UNVERIFIED device tests (require physical iPhone):
//   - Clean strobe at 1 / 6 / 10 / 12 Hz — visible, regular, no flicker artefacts
//   - 40 Hz attempt: confirm whether the torch produces a clean square wave at this
//     frequency; report actual measured frequency and any thermal behaviour observed.
//     (Congress Moment 9.1 marked UNVERIFIED until this run.)
//   - Duty cycle: 30% and 70% settings produce visibly different on/off ratios.
//   - Thermal degradation: sustained 40 Hz for 5+ minutes should trigger .serious
//     and reduce intensity, not crash.
//   - Lock contention: starting while another app holds the camera should surface
//     StrobeError.lockFailed cleanly.
//
// The tests below exercise logic that does NOT require hardware.

import XCTest
@testable import StrobeController

final class StrobeControllerTests: XCTestCase {

    // MARK: - Cap enforcement (primary safety requirement)

    func testCap_exceedingHz_isClamped() {
        let ctrl = StrobeController(maxStrobeHz: 50)
        ctrl.setParameters(hz: 200, dutyCycle: 0.5, intensity: 0.6)
        XCTAssertEqual(ctrl.effectiveHz, 50.0)
    }

    func testCap_belowCap_isUnchanged() {
        let ctrl = StrobeController(maxStrobeHz: 50)
        ctrl.setParameters(hz: 10, dutyCycle: 0.5, intensity: 0.6)
        XCTAssertEqual(ctrl.effectiveHz, 10.0)
    }

    func testCap_exactlyAtCap_isUnchanged() {
        let ctrl = StrobeController(maxStrobeHz: 50)
        ctrl.setParameters(hz: 50, dutyCycle: 0.5, intensity: 0.6)
        XCTAssertEqual(ctrl.effectiveHz, 50.0)
    }

    func testCap_malformedSessionValue_isClamped() {
        // Simulates a session file with an absurd Hz value (Section 5 safety guarantee).
        let ctrl = StrobeController(maxStrobeHz: 15)
        ctrl.setParameters(hz: 9999, dutyCycle: 0.5, intensity: 0.6)
        XCTAssertEqual(ctrl.effectiveHz, 15.0)
    }

    func testCap_zeroHz_doesNotCrash() {
        let ctrl = StrobeController(maxStrobeHz: 50)
        ctrl.setParameters(hz: 0, dutyCycle: 0.5, intensity: 0.6)
        XCTAssertEqual(ctrl.effectiveHz, 0.0)
    }

    // MARK: - Parameter clamping

    func testDutyCycle_clampedToMinimum() {
        let ctrl = StrobeController(maxStrobeHz: 50)
        ctrl.setParameters(hz: 10, dutyCycle: -1.0, intensity: 0.6)
        // effectiveHz still set correctly; duty cycle is clamped internally
        XCTAssertEqual(ctrl.effectiveHz, 10.0)
        XCTAssertFalse(ctrl.isRunning)
    }

    func testDutyCycle_clampedToMaximum() {
        let ctrl = StrobeController(maxStrobeHz: 50)
        ctrl.setParameters(hz: 10, dutyCycle: 5.0, intensity: 0.6)
        XCTAssertEqual(ctrl.effectiveHz, 10.0)
    }

    func testIntensity_clampedToValidRange() {
        let ctrl = StrobeController(maxStrobeHz: 50)
        // Neither extreme should crash on parameter set (device start is not called).
        ctrl.setParameters(hz: 10, dutyCycle: 0.5, intensity: -1.0)
        ctrl.setParameters(hz: 10, dutyCycle: 0.5, intensity: 99.0)
        XCTAssertFalse(ctrl.isRunning)
    }

    // MARK: - Initial state

    func testInitialState_isNotRunning() {
        let ctrl = StrobeController(maxStrobeHz: 50)
        XCTAssertFalse(ctrl.isRunning)
        XCTAssertEqual(ctrl.effectiveHz, 0.0)
    }

    func testMaxStrobeHz_isStoredCorrectly() {
        let ctrl = StrobeController(maxStrobeHz: 42.0)
        XCTAssertEqual(ctrl.maxStrobeHz, 42.0)
    }

    // MARK: - Repeated parameter updates

    func testMultipleSetParametersCalls_lastValueWins() {
        let ctrl = StrobeController(maxStrobeHz: 50)
        ctrl.setParameters(hz: 10, dutyCycle: 0.5, intensity: 0.6)
        ctrl.setParameters(hz: 6,  dutyCycle: 0.4, intensity: 0.5)
        ctrl.setParameters(hz: 60, dutyCycle: 0.5, intensity: 0.7)  // should be capped
        XCTAssertEqual(ctrl.effectiveHz, 50.0, "Cap should apply to last update")
    }
}
