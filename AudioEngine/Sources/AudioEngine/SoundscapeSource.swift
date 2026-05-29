// UNVERIFIED — requires device test. No torch/audio hardware in simulator.
import AVFoundation

// MARK: - Protocol

/// Abstraction over the audio bed playing under the binaural tones.
///
/// Current implementation: `GeneratedSoundscapeMixer` (Option A — real-time pink noise).
/// Future: `FileSoundscapeMixer` reading from `Session.audioBedAsset` (GarageBand stems
/// or licensed beds). Conform to this protocol and branch on `audioBedAsset != nil`
/// in `AudioEngineController` to swap implementations without touching anything else.
protocol SoundscapeSource: AnyObject {
    /// Attach all internal AVAudioNodes to the engine before connecting.
    func attach(to engine: AVAudioEngine)
    /// Wire internal nodes into the graph, ending at `mixer`.
    func connect(to mixer: AVAudioMixerNode, in engine: AVAudioEngine, format: AVAudioFormat)
    func start()
    func stop()
    /// Output gain [0–1]. Written from the session thread; read from the render thread.
    func setGain(_ gain: Float)
}

// MARK: - Real-time-safe PRNG (Knuth LCG — allocation-free)

private struct _PRNG {
    private var state: UInt64

    init(seed: UInt64 = 12345) { state = seed }

    mutating func nextFloat() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let x = Int32(bitPattern: UInt32(state >> 32))
        return Float(x) / Float(Int32.max)  // ≈ [-1, 1]
    }
}

// MARK: - Pink noise state (Paul Kellet 7-coefficient approximation, −3 dB/octave)

private struct _PinkNoiseState {
    private var b0: Double = 0, b1: Double = 0, b2: Double = 0
    private var b3: Double = 0, b4: Double = 0, b5: Double = 0, b6: Double = 0
    private var prng = _PRNG()

    mutating func nextSample() -> Float {
        let w = Double(prng.nextFloat())
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return Float(pink * 0.11)  // normalise to ≈ ±1
    }
}

// MARK: - Render state (reference type so the render block can capture it)

/// Holds all mutable state accessed by the soundscape render block.
/// `gain` is the one cross-thread property — see threading note in `BinauralSynth._RenderState`.
private final class _SoundscapeRenderState {
    var pink = _PinkNoiseState()
    var gain: Float = 0.35
}

// MARK: - Generated soundscape (Option A)

/// Real-time pink noise through a medium-room reverb.
/// No audio files, no licensing burden, no bundle impact.
/// Pink noise rolls off at higher frequencies, leaving the 200–500 Hz
/// binaural carrier band relatively unmasked.
final class GeneratedSoundscapeMixer: SoundscapeSource {

    private let sourceNode: AVAudioSourceNode
    private let reverbUnit: AVAudioUnitReverb
    private let renderState: _SoundscapeRenderState

    init(format: AVAudioFormat) {
        let state = _SoundscapeRenderState()
        self.renderState = state

        reverbUnit = AVAudioUnitReverb()
        reverbUnit.loadFactoryPreset(.mediumRoom)
        reverbUnit.wetDryMix = 35   // 35% wet — spacious without washing out the beats

        // Mono source; the mixer spreads it equally to both ears.
        sourceNode = AVAudioSourceNode(format: format) { [unowned state] isSilence, _, frameCount, audioBufferList in
            isSilence.pointee = false
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let ptr = abl.first?.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            let g     = state.gain
            let count = Int(frameCount)
            for i in 0..<count {
                ptr[i] = state.pink.nextSample() * g
            }
            return noErr
        }
    }

    // MARK: SoundscapeSource

    func attach(to engine: AVAudioEngine) {
        engine.attach(sourceNode)
        engine.attach(reverbUnit)
    }

    func connect(to mixer: AVAudioMixerNode, in engine: AVAudioEngine, format: AVAudioFormat) {
        engine.connect(sourceNode, to: reverbUnit, format: format)
        engine.connect(reverbUnit, to: mixer, format: format)
    }

    func start() {}  // AVAudioSourceNode begins rendering when the engine starts.
    func stop()  {}

    func setGain(_ gain: Float) {
        renderState.gain = gain
    }
}
