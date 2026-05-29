// UNVERIFIED — requires device test. No torch/audio hardware in simulator.
import AVFoundation

// MARK: - AudioEngineController

/// Owns the `AVAudioEngine` graph and exposes a minimal interface for `SessionRunner`.
///
/// Graph topology (Engine mode):
///
///   BinauralSynth.node (stereo)   soundscape chain (mono → reverb)
///             │                              │
///             └──────── mainMixer ───────────┘
///                            │
///                       outputNode
///
/// `SessionRunner` calls `setParameters` on every CurveEvaluator tick to drive
/// carrier/beat frequencies and soundscape gain in real time.
///
/// Bring-your-own audio mode: `BinauralSynth` is not used; only `StrobeController`
/// runs. That branching lives in `SessionRunner` (Phase 4).
public final class AudioEngineController {

    private let engine       = AVAudioEngine()
    private let mainMixer    = AVAudioMixerNode()
    private let audioBedAsset: String?

    // Populated in buildGraph(), which runs at start().
    private var synth: BinauralSynth?
    private var soundscape: (any SoundscapeSource)?
    private var sampleRate: Double = 44100

    // MARK: Init

    /// - Parameter audioBedAsset: When non-nil, a future `FileSoundscapeMixer` will
    ///   be used instead of the generated ambient (Section 9.4 seam). Currently
    ///   ignored — `GeneratedSoundscapeMixer` is always used at v1.
    public init(audioBedAsset: String? = nil) {
        self.audioBedAsset = audioBedAsset
    }

    // MARK: - Lifecycle

    /// Build the AVAudioEngine graph and start audio rendering.
    /// Must be called on the main thread. Throws if the engine fails to start.
    public func start() throws {
        buildGraph()
        try engine.start()
        soundscape?.start()
    }

    public func pause() {
        engine.pause()
    }

    public func stop() {
        soundscape?.stop()
        engine.stop()
    }

    public var isRunning: Bool { engine.isRunning }

    /// The `mHostTime` of the most recent audio render cycle.
    /// Passed to `StrobeController.resync(toAudioHostTime:)` by `SessionRunner` (~5 s cadence)
    /// to eliminate long-term drift between the strobe timer and the audio clock (Path C).
    public var currentAudioHostTime: UInt64 {
        engine.outputNode.lastRenderTime?.hostTime ?? 0
    }

    // MARK: - Real-time parameter updates (session thread)

    /// Called by SessionRunner on every CurveEvaluator tick.
    /// All paths through this method are allocation-free and lock-free.
    public func setParameters(carrierHz: Double, beatHz: Double, soundscapeGain: Float) {
        synth?.setFrequencies(carrierHz: carrierHz, beatHz: beatHz, sampleRate: sampleRate)
        soundscape?.setGain(soundscapeGain)
    }

    public func setBinauralGain(_ gain: Float) {
        synth?.setGain(gain)
    }

    // MARK: - Graph construction

    private func buildGraph() {
        // Query the hardware sample rate first — avoids format-conversion overhead.
        let hwRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        sampleRate = hwRate > 0 ? hwRate : 44100   // 44100 fallback for test environments

        let stereoFormat = Self.makeFormat(sampleRate: sampleRate, channels: 2)
        let monoFormat   = Self.makeFormat(sampleRate: sampleRate, channels: 1)

        let s = BinauralSynth(format: stereoFormat, sampleRate: sampleRate)
        synth = s

        // audioBedAsset != nil → future FileSoundscapeMixer; nil → generated ambient.
        let sc = GeneratedSoundscapeMixer(format: monoFormat)
        soundscape = sc

        // Attach all nodes before wiring.
        engine.attach(s.node)
        engine.attach(mainMixer)
        sc.attach(to: engine)

        // Binaural synth (stereo) → main mixer
        engine.connect(s.node, to: mainMixer, format: stereoFormat)

        // Soundscape (mono → reverb → main mixer)
        sc.connect(to: mainMixer, in: engine, format: monoFormat)

        // Main mixer → hardware output (nil lets the engine choose the output format)
        engine.connect(mainMixer, to: engine.outputNode, format: nil)

        mainMixer.outputVolume = 1.0
    }

    private static func makeFormat(sampleRate: Double, channels: AVAudioChannelCount) -> AVAudioFormat {
        guard let f = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) else {
            preconditionFailure("Could not create AVAudioFormat(\(channels)ch @ \(sampleRate) Hz)")
        }
        return f
    }
}
