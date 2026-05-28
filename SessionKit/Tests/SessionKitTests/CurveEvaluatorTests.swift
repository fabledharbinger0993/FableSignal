import XCTest
@testable import SessionKit

final class CurveEvaluatorTests: XCTestCase {

    // MARK: - StrobeCurve: boundary and edge cases

    func testStrobe_emptyKeyframes_returnsDefaultZeroState() {
        let curve = StrobeCurve(keyframes: [], interpolation: .linear)
        let state = CurveEvaluator.evaluate(curve, at: 30)
        XCTAssertEqual(state.hz, 0)
        XCTAssertEqual(state.dutyCycle, 0.5)
        XCTAssertEqual(state.intensity, 0)
    }

    func testStrobe_singleKeyframe_isConstantAcrossAllT() {
        let curve = StrobeCurve(
            keyframes: [StrobeKeyframe(tSec: 10, hz: 8, dutyCycle: 0.5, intensity: 0.6)],
            interpolation: .linear
        )
        for t in [-10.0, 0.0, 10.0, 50.0, 1000.0] {
            let s = CurveEvaluator.evaluate(curve, at: t)
            XCTAssertEqual(s.hz, 8,   "t=\(t)")
            XCTAssertEqual(s.dutyCycle, 0.5, "t=\(t)")
            XCTAssertEqual(s.intensity, 0.6, "t=\(t)")
        }
    }

    func testStrobe_beforeFirstKeyframe_holdsFirstValue() {
        let curve = makeSimpleStrobeCurve()
        let s = CurveEvaluator.evaluate(curve, at: -5)
        XCTAssertEqual(s.hz, 10)
    }

    func testStrobe_atFirstKeyframeExact_returnsFirstValue() {
        let curve = makeSimpleStrobeCurve()
        let s = CurveEvaluator.evaluate(curve, at: 0)
        XCTAssertEqual(s.hz, 10)
    }

    func testStrobe_atLastKeyframeExact_returnsLastValue() {
        let curve = makeSimpleStrobeCurve()
        let s = CurveEvaluator.evaluate(curve, at: 60)
        XCTAssertEqual(s.hz, 6)
    }

    func testStrobe_afterLastKeyframe_holdsLastValue() {
        let curve = makeSimpleStrobeCurve()
        let s = CurveEvaluator.evaluate(curve, at: 120)
        XCTAssertEqual(s.hz, 6)
    }

    func testStrobe_atIntermediateKeyframeExact_returnsExactValue() {
        let curve = StrobeCurve(
            keyframes: [
                StrobeKeyframe(tSec:  0, hz: 10, dutyCycle: 0.5, intensity: 0.6),
                StrobeKeyframe(tSec: 30, hz:  8, dutyCycle: 0.5, intensity: 0.6),
                StrobeKeyframe(tSec: 60, hz:  6, dutyCycle: 0.5, intensity: 0.6),
            ],
            interpolation: .linear
        )
        let s = CurveEvaluator.evaluate(curve, at: 30)
        XCTAssertEqual(s.hz, 8, accuracy: 1e-10)
    }

    // MARK: - StrobeCurve: linear interpolation

    func testStrobe_midpointLinear_isExactMidpoint() {
        let curve = makeSimpleStrobeCurve(interpolation: .linear)
        // Midpoint between t=0 (hz=10) and t=60 (hz=6): expected hz = 8
        let s = CurveEvaluator.evaluate(curve, at: 30)
        XCTAssertEqual(s.hz, 8.0, accuracy: 1e-10)
    }

    func testStrobe_quarterPointLinear() {
        let curve = makeSimpleStrobeCurve(interpolation: .linear)
        // t=15 (25% through 0→60), hz: 10 + (6-10)*0.25 = 10 - 1 = 9
        let s = CurveEvaluator.evaluate(curve, at: 15)
        XCTAssertEqual(s.hz, 9.0, accuracy: 1e-10)
    }

    // MARK: - StrobeCurve: easeInOut interpolation

    func testStrobe_midpointEaseInOut_matchesMidpointLinear() {
        // smoothstep(0.5) = 0.5, so midpoint is the same as linear
        let linear    = makeSimpleStrobeCurve(interpolation: .linear)
        let easeInOut = makeSimpleStrobeCurve(interpolation: .easeInOut)
        let sL = CurveEvaluator.evaluate(linear,    at: 30)
        let sE = CurveEvaluator.evaluate(easeInOut, at: 30)
        XCTAssertEqual(sL.hz, sE.hz, accuracy: 1e-10)
    }

    func testStrobe_quarterPointEaseInOut_differsfromLinear() {
        // At t=0.25 in [0,1]: smoothstep(0.25) = 3(0.0625) - 2(0.015625) = 0.15625
        // linear gives t=0.25; easeInOut gives t=0.15625
        // With hz 10→6 (delta -4): linear=9.0, easeInOut=10-4*0.15625=9.375
        let linear    = makeSimpleStrobeCurve(interpolation: .linear)
        let easeInOut = makeSimpleStrobeCurve(interpolation: .easeInOut)
        let sL = CurveEvaluator.evaluate(linear,    at: 15)
        let sE = CurveEvaluator.evaluate(easeInOut, at: 15)
        XCTAssertEqual(sL.hz, 9.0,   accuracy: 1e-10)
        XCTAssertEqual(sE.hz, 9.375, accuracy: 1e-10)
        XCTAssertNotEqual(sL.hz, sE.hz)
    }

    func testStrobe_threeQuarterPointEaseInOut() {
        // smoothstep(0.75) = 3(0.5625) - 2(0.421875) = 1.6875 - 0.84375 = 0.84375
        // hz = 10 - 4 * 0.84375 = 10 - 3.375 = 6.625
        let curve = makeSimpleStrobeCurve(interpolation: .easeInOut)
        let s = CurveEvaluator.evaluate(curve, at: 45)
        XCTAssertEqual(s.hz, 6.625, accuracy: 1e-10)
    }

    // MARK: - StrobeCurve: all three fields interpolate

    func testStrobe_allFieldsInterpolateLinear() {
        let curve = StrobeCurve(
            keyframes: [
                StrobeKeyframe(tSec:  0, hz: 10, dutyCycle: 0.4, intensity: 0.5),
                StrobeKeyframe(tSec: 10, hz:  5, dutyCycle: 0.6, intensity: 0.7),
            ],
            interpolation: .linear
        )
        let s = CurveEvaluator.evaluate(curve, at: 5)
        XCTAssertEqual(s.hz,        7.5, accuracy: 1e-10)
        XCTAssertEqual(s.dutyCycle, 0.5, accuracy: 1e-10)
        XCTAssertEqual(s.intensity, 0.6, accuracy: 1e-10)
    }

    // MARK: - Safety cap

    func testStrobe_safetyCapClampsExceedingHz() {
        let curve = makeSimpleStrobeCurve() // starts at 10 Hz
        let s = CurveEvaluator.evaluate(curve, at: 0, cappedTo: 8.0)
        XCTAssertEqual(s.hz, 8.0)
    }

    func testStrobe_safetyCapPreservesOtherFields() {
        let curve = StrobeCurve(
            keyframes: [StrobeKeyframe(tSec: 0, hz: 40, dutyCycle: 0.5, intensity: 0.6)],
            interpolation: .linear
        )
        let s = CurveEvaluator.evaluate(curve, at: 0, cappedTo: 30.0)
        XCTAssertEqual(s.hz, 30.0)
        XCTAssertEqual(s.dutyCycle, 0.5)
        XCTAssertEqual(s.intensity, 0.6)
    }

    func testStrobe_safetyCapDoesNotAlterValueBelowCap() {
        let curve = StrobeCurve(
            keyframes: [StrobeKeyframe(tSec: 0, hz: 6, dutyCycle: 0.5, intensity: 0.6)],
            interpolation: .linear
        )
        let s = CurveEvaluator.evaluate(curve, at: 0, cappedTo: 50.0)
        XCTAssertEqual(s.hz, 6.0)
    }

    func testStrobe_safetyCapExactlyAtCap_notClamped() {
        let curve = StrobeCurve(
            keyframes: [StrobeKeyframe(tSec: 0, hz: 15, dutyCycle: 0.5, intensity: 0.6)],
            interpolation: .linear
        )
        let s = CurveEvaluator.evaluate(curve, at: 0, cappedTo: 15.0)
        XCTAssertEqual(s.hz, 15.0)
    }

    func testStrobe_malformedSessionAboveCap_isClamped() {
        // Simulates a session file containing hz values exceeding maxStrobeHz
        let curve = StrobeCurve(
            keyframes: [
                StrobeKeyframe(tSec:  0, hz: 200, dutyCycle: 0.5, intensity: 1.0),
                StrobeKeyframe(tSec: 60, hz: 200, dutyCycle: 0.5, intensity: 1.0),
            ],
            interpolation: .linear
        )
        let safety = SafetyProfile(maxStrobeHz: 50, requiresHeadphones: true, photosensitiveGateRequired: true)
        for t in [0.0, 15.0, 30.0, 45.0, 60.0] {
            let s = CurveEvaluator.evaluate(curve, at: t, cappedTo: safety.maxStrobeHz)
            XCTAssertLessThanOrEqual(s.hz, safety.maxStrobeHz, "t=\(t) should be capped")
        }
    }

    // MARK: - BinauralCurve: boundary and edge cases

    func testBinaural_emptyKeyframes_returnsDefaultZeroState() {
        let curve = BinauralCurve(keyframes: [], interpolation: .linear)
        let s = CurveEvaluator.evaluate(curve, at: 30)
        XCTAssertEqual(s.carrierHz, 0)
        XCTAssertEqual(s.beatHz,    0)
        XCTAssertEqual(s.gain,      0)
    }

    func testBinaural_singleKeyframe_isConstantAcrossAllT() {
        let curve = BinauralCurve(
            keyframes: [BinauralKeyframe(tSec: 10, carrierHz: 200, beatHz: 6, gain: 0.8)],
            interpolation: .linear
        )
        for t in [-10.0, 0.0, 10.0, 300.0] {
            let s = CurveEvaluator.evaluate(curve, at: t)
            XCTAssertEqual(s.carrierHz, 200, "t=\(t)")
            XCTAssertEqual(s.beatHz,      6, "t=\(t)")
            XCTAssertEqual(s.gain,      0.8, "t=\(t)")
        }
    }

    func testBinaural_beforeFirstKeyframe_holdsFirstValue() {
        let curve = makeSimpleBinauralCurve()
        let s = CurveEvaluator.evaluate(curve, at: -5)
        XCTAssertEqual(s.beatHz, 10)
    }

    func testBinaural_atFirstKeyframeExact_returnsFirstValue() {
        let curve = makeSimpleBinauralCurve()
        let s = CurveEvaluator.evaluate(curve, at: 0)
        XCTAssertEqual(s.beatHz, 10)
    }

    func testBinaural_atLastKeyframeExact_returnsLastValue() {
        let curve = makeSimpleBinauralCurve()
        let s = CurveEvaluator.evaluate(curve, at: 60)
        XCTAssertEqual(s.beatHz, 6)
    }

    func testBinaural_afterLastKeyframe_holdsLastValue() {
        let curve = makeSimpleBinauralCurve()
        let s = CurveEvaluator.evaluate(curve, at: 120)
        XCTAssertEqual(s.beatHz, 6)
    }

    func testBinaural_midpointLinear() {
        let curve = makeSimpleBinauralCurve(interpolation: .linear)
        // beatHz 10→6 over 0→60s: at t=30, expected=8
        let s = CurveEvaluator.evaluate(curve, at: 30)
        XCTAssertEqual(s.beatHz, 8.0, accuracy: 1e-10)
    }

    func testBinaural_quarterPointEaseInOut_differsfromLinear() {
        // At t=0.25: smoothstep=0.15625
        // beatHz linear: 10-4*0.25=9.0; easeInOut: 10-4*0.15625=9.375
        let linear    = makeSimpleBinauralCurve(interpolation: .linear)
        let easeInOut = makeSimpleBinauralCurve(interpolation: .easeInOut)
        let sL = CurveEvaluator.evaluate(linear,    at: 15)
        let sE = CurveEvaluator.evaluate(easeInOut, at: 15)
        XCTAssertEqual(sL.beatHz, 9.0,   accuracy: 1e-10)
        XCTAssertEqual(sE.beatHz, 9.375, accuracy: 1e-10)
    }

    func testBinaural_allFieldsInterpolateLinear() {
        let curve = BinauralCurve(
            keyframes: [
                BinauralKeyframe(tSec:  0, carrierHz: 200, beatHz: 10, gain: 0.8),
                BinauralKeyframe(tSec: 10, carrierHz: 250, beatHz:  5, gain: 0.4),
            ],
            interpolation: .linear
        )
        let s = CurveEvaluator.evaluate(curve, at: 5)
        XCTAssertEqual(s.carrierHz, 225.0, accuracy: 1e-10)
        XCTAssertEqual(s.beatHz,    7.5,   accuracy: 1e-10)
        XCTAssertEqual(s.gain,      0.6,   accuracy: 1e-10)
    }

    // MARK: - Helpers

    private func makeSimpleStrobeCurve(
        interpolation: CurveInterpolation = .linear
    ) -> StrobeCurve {
        StrobeCurve(
            keyframes: [
                StrobeKeyframe(tSec:  0, hz: 10, dutyCycle: 0.5, intensity: 0.6),
                StrobeKeyframe(tSec: 60, hz:  6, dutyCycle: 0.5, intensity: 0.6),
            ],
            interpolation: interpolation
        )
    }

    private func makeSimpleBinauralCurve(
        interpolation: CurveInterpolation = .linear
    ) -> BinauralCurve {
        BinauralCurve(
            keyframes: [
                BinauralKeyframe(tSec:  0, carrierHz: 200, beatHz: 10, gain: 0.8),
                BinauralKeyframe(tSec: 60, carrierHz: 200, beatHz:  6, gain: 0.8),
            ],
            interpolation: interpolation
        )
    }
}
