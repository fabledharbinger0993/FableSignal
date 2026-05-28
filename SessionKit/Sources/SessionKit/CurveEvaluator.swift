// MARK: - Result types

/// Evaluated strobe parameters at a point in time.
public struct StrobeState: Equatable, Sendable {
    public let hz: Double
    public let dutyCycle: Double
    public let intensity: Double

    public init(hz: Double, dutyCycle: Double, intensity: Double) {
        self.hz = hz
        self.dutyCycle = dutyCycle
        self.intensity = intensity
    }
}

/// Evaluated binaural parameters at a point in time.
public struct BinauralState: Equatable, Sendable {
    public let carrierHz: Double
    public let beatHz: Double
    public let gain: Double

    public init(carrierHz: Double, beatHz: Double, gain: Double) {
        self.carrierHz = carrierHz
        self.beatHz = beatHz
        self.gain = gain
    }
}

// MARK: - Evaluator

/// Stateless interpolation of StrobeCurve and BinauralCurve at arbitrary time t.
///
/// Behavior at boundaries:
///   - t < first keyframe tSec → returns first keyframe values (hold first)
///   - t > last  keyframe tSec → returns last  keyframe values (hold last)
///   - t exactly on a keyframe → returns that keyframe's exact values
///   - single-keyframe curve   → constant regardless of t
///   - empty keyframes         → zero-value default state
public enum CurveEvaluator {

    // MARK: Strobe

    public static func evaluate(_ curve: StrobeCurve, at time: Double) -> StrobeState {
        let kf = curve.keyframes
        guard !kf.isEmpty else {
            return StrobeState(hz: 0, dutyCycle: 0.5, intensity: 0)
        }
        if kf.count == 1 {
            return stateFrom(kf[0])
        }
        if time <= kf[0].tSec { return stateFrom(kf[0]) }
        if time >= kf[kf.count - 1].tSec { return stateFrom(kf[kf.count - 1]) }

        let (a, b) = bracket(kf, at: time, tKey: { $0.tSec })
        let t = blendFactor(from: a.tSec, to: b.tSec, at: time, mode: curve.interpolation)
        return StrobeState(
            hz:        lerp(a.hz,        b.hz,        t),
            dutyCycle: lerp(a.dutyCycle, b.dutyCycle, t),
            intensity: lerp(a.intensity, b.intensity, t)
        )
    }

    /// Evaluate with the runtime safety cap applied (defense-in-depth layer;
    /// StrobeController enforces the same cap independently at the hardware call site).
    public static func evaluate(
        _ curve: StrobeCurve,
        at time: Double,
        cappedTo maxHz: Double
    ) -> StrobeState {
        let s = evaluate(curve, at: time)
        guard s.hz > maxHz else { return s }
        return StrobeState(hz: maxHz, dutyCycle: s.dutyCycle, intensity: s.intensity)
    }

    // MARK: Binaural

    public static func evaluate(_ curve: BinauralCurve, at time: Double) -> BinauralState {
        let kf = curve.keyframes
        guard !kf.isEmpty else {
            return BinauralState(carrierHz: 0, beatHz: 0, gain: 0)
        }
        if kf.count == 1 {
            return stateFrom(kf[0])
        }
        if time <= kf[0].tSec { return stateFrom(kf[0]) }
        if time >= kf[kf.count - 1].tSec { return stateFrom(kf[kf.count - 1]) }

        let (a, b) = bracket(kf, at: time, tKey: { $0.tSec })
        let t = blendFactor(from: a.tSec, to: b.tSec, at: time, mode: curve.interpolation)
        return BinauralState(
            carrierHz: lerp(a.carrierHz, b.carrierHz, t),
            beatHz:    lerp(a.beatHz,    b.beatHz,    t),
            gain:      lerp(a.gain,      b.gain,      t)
        )
    }

    // MARK: Helpers

    private static func stateFrom(_ kf: StrobeKeyframe) -> StrobeState {
        StrobeState(hz: kf.hz, dutyCycle: kf.dutyCycle, intensity: kf.intensity)
    }

    private static func stateFrom(_ kf: BinauralKeyframe) -> BinauralState {
        BinauralState(carrierHz: kf.carrierHz, beatHz: kf.beatHz, gain: kf.gain)
    }

    /// Returns the two keyframes that bracket `time` (assumes time is strictly interior).
    private static func bracket<T>(
        _ keyframes: [T],
        at time: Double,
        tKey: (T) -> Double
    ) -> (T, T) {
        // Linear scan is fine for small keyframe counts typical in a session segment.
        var upperIndex = keyframes.count - 1
        for i in 1..<keyframes.count {
            if tKey(keyframes[i]) > time {
                upperIndex = i
                break
            }
        }
        return (keyframes[upperIndex - 1], keyframes[upperIndex])
    }

    private static func blendFactor(
        from tStart: Double,
        to tEnd: Double,
        at time: Double,
        mode: CurveInterpolation
    ) -> Double {
        guard tEnd > tStart else { return 0 }
        let raw = (time - tStart) / (tEnd - tStart)
        let clamped = max(0, min(1, raw))
        switch mode {
        case .linear:    return clamped
        case .easeInOut: return smoothstep(clamped)
        }
    }

    /// Smoothstep: f(t) = 3t² − 2t³  (zero-derivative at t=0 and t=1).
    private static func smoothstep(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}
