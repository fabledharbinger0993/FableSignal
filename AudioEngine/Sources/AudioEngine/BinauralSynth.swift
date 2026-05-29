// UNVERIFIED — requires device test. No torch/audio hardware in simulator.
import AVFoundation

// MARK: - Render state (render-thread-private)

/// All mutable audio state owned by the render thread.
/// `targetLeft/RightIncrement` are the single exception: written from the session thread,
/// read from the render thread. On ARM64, aligned Double r/w is atomic at the hardware
/// level; a torn read costs at most one render buffer (~5 ms) of slightly stale frequency,
/// which is inaudible. No lock is used here because a lock on the real-time audio thread
/// can cause priority inversion and audible glitches.
private final class _RenderState {
    // Render-thread-only: phase and ramping state
    var leftPhase: Double = 0
    var rightPhase: Double = 0
    var leftCurrentIncrement: Double = 0
    var rightCurrentIncrement: Double = 0

    // Cross-thread: session thread writes, render thread reads.
    var leftTargetIncrement: Double = 0
    var rightTargetIncrement: Double = 0

    // Smoothing coefficient for one-pole frequency ramp (~10 ms time constant).
    let rampCoefficient: Double

    // Gain multiplied onto every output sample.
    var gain: Float = 1.0

    init(sampleRate: Double) {
        rampCoefficient = 1.0 - exp(-1.0 / (sampleRate * 0.010))
    }
}

// MARK: - BinauralSynth

/// Stereo `AVAudioSourceNode` that generates a binaural beat by producing two independent
/// pure-sine tones: left channel at `carrierHz`, right channel at `carrierHz + beatHz`.
///
/// Phase continuity invariant: the phase accumulators are NEVER reset. Only the
/// per-sample frequency increment changes. This is what makes frequency transitions
/// click-free — there is no discontinuity in the waveform.
///
/// Engine mode only. Requires headphones with hard L/R separation.
final class BinauralSynth {

    private(set) var node: AVAudioSourceNode!
    private let state: _RenderState

    init(format: AVAudioFormat, sampleRate: Double) {
        let s = _RenderState(sampleRate: sampleRate)
        self.state = s

        node = AVAudioSourceNode(format: format) { [unowned s] isSilence, _, frameCount, audioBufferList in
            isSilence.pointee = false

            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2,
                  let lPtr = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let rPtr = abl[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }

            let rc    = s.rampCoefficient
            let gain  = s.gain
            let count = Int(frameCount)

            for i in 0..<count {
                // One-pole ramp: smoothly move current increment toward target.
                s.leftCurrentIncrement  += (s.leftTargetIncrement  - s.leftCurrentIncrement)  * rc
                s.rightCurrentIncrement += (s.rightTargetIncrement - s.rightCurrentIncrement) * rc

                s.leftPhase  += s.leftCurrentIncrement
                s.rightPhase += s.rightCurrentIncrement

                // Wrap phases to [-π, π] to prevent loss of floating-point precision
                // over long sessions (otherwise phase grows unbounded).
                if s.leftPhase  >  .pi { s.leftPhase  -= 2 * .pi }
                if s.rightPhase >  .pi { s.rightPhase -= 2 * .pi }

                lPtr[i] = Float(sin(s.leftPhase))  * gain
                rPtr[i] = Float(sin(s.rightPhase)) * gain
            }
            return noErr
        }
    }

    // MARK: - Session-thread interface

    /// Update target carrier and beat frequencies. The render block ramps toward
    /// these values smoothly; call at any time without audio artifacts.
    func setFrequencies(carrierHz: Double, beatHz: Double, sampleRate: Double) {
        let twoPiOverSr = 2.0 * .pi / sampleRate
        state.leftTargetIncrement  = carrierHz            * twoPiOverSr
        state.rightTargetIncrement = (carrierHz + beatHz) * twoPiOverSr
    }

    func setGain(_ gain: Float) {
        state.gain = gain
    }
}
