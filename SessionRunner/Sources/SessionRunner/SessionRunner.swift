// UNVERIFIED — device-dependent layers (AudioEngineController, StrobeController)
// require a physical iOS device. Logic paths are testable in isolation.
import AVFoundation
import SessionKit
import AudioEngine
import StrobeController

// MARK: - Audio mode

/// Whether the app generates its own binaural tones or the user provides music.
public enum AudioMode: Equatable {
    /// BinauralSynth + soundscape active. Requires headphones with hard L/R separation.
    case engine
    /// User's own music plays via another app. Strobe runs standalone; binaural inactive.
    case bringYourOwn
}

// MARK: - Runner state

public enum SessionRunnerState: Equatable {
    case idle
    case running
    case paused
    case completed
}

// MARK: - SessionRunner

/// Orchestrates `AudioEngineController` and `StrobeController` against a `Session`.
///
/// Update loop (Path C):
///   A 30 Hz `DispatchSourceTimer` on the main queue calls `CurveEvaluator` on each
///   tick to get current strobe and binaural parameters, then pushes them to both
///   hardware controllers. Every `resyncInterval` ticks, the audio engine's render
///   clock (`currentAudioHostTime`) is passed to `StrobeController.resync(toAudioHostTime:)`
///   to eliminate long-term strobe/beat drift.
///
/// Mode branching:
///   `.engine` — both `AudioEngineController` and `StrobeController` run.
///   `.bringYourOwn` — only `StrobeController` runs; binaural curves are ignored.
///
/// Interruption: call `stop()` immediately from the `AVAudioSession` interruption
/// notification handler (Phase 6 wires this). `stop()` is safe to call from any
/// thread; it shuts down both controllers synchronously before returning.
public final class SessionRunner {

    // MARK: Public interface

    public private(set) var state: SessionRunnerState = .idle

    /// Called on the main thread when the state changes.
    public var onStateChange: ((SessionRunnerState) -> Void)?
    /// Called on the main thread when the session completes naturally.
    public var onSessionEnd: (() -> Void)?
    /// Called on the main thread when thermal pressure forces an emergency stop.
    public var onThermalShutdown: (() -> Void)?

    // MARK: Private — session configuration

    private let session: Session
    private let audioMode: AudioMode

    // MARK: Private — hardware controllers

    private let audioEngine: AudioEngineController
    private let strobeController: StrobeController

    // MARK: Private — update loop

    private var updateTimer: DispatchSourceTimer?
    private var isPaused = false
    private let updateHz: Double = 30
    // Resync every 5 seconds (30 Hz × 5 s = 150 ticks).
    private let resyncInterval = 150
    private var tickCount = 0

    // MARK: Private — elapsed time tracking

    private var _runningStartTime: Date?
    private var _pausedAccumulator: TimeInterval = 0

    private var sessionElapsed: TimeInterval {
        guard let start = _runningStartTime else { return _pausedAccumulator }
        return Date().timeIntervalSince(start) + _pausedAccumulator
    }

    // MARK: - Init

    public init(session: Session, audioMode: AudioMode) {
        self.session      = session
        self.audioMode    = audioMode
        self.audioEngine  = AudioEngineController(audioBedAsset: session.audioBedAsset)
        self.strobeController = StrobeController(maxStrobeHz: session.safety.maxStrobeHz)
    }

    // MARK: - Lifecycle

    /// Start the session from the beginning.
    ///
    /// - Throws: `StrobeError` if the torch lock cannot be acquired.
    ///           AVFoundation errors if the audio engine fails to start.
    public func start() throws {
        _pausedAccumulator = 0
        _runningStartTime  = Date()
        isPaused           = false
        tickCount          = 0

        strobeController.onThermalShutdown = { [weak self] in
            self?.stop()
            self?.onThermalShutdown?()
        }

        if audioMode == .engine {
            try audioEngine.start()
        }
        try strobeController.start()

        startUpdateLoop()
        setState(.running)
    }

    /// Suspend the session — torch off, audio paused, timer skips.
    public func pause() {
        guard state == .running else { return }
        isPaused = true
        _pausedAccumulator += Date().timeIntervalSince(_runningStartTime ?? Date())
        _runningStartTime  = nil

        strobeController.stop()
        if audioMode == .engine { audioEngine.pause() }
        setState(.paused)
    }

    /// Resume after a pause — re-acquires the torch lock, restarts audio.
    public func resume() throws {
        guard state == .paused else { return }

        _runningStartTime = Date()
        isPaused          = false

        if audioMode == .engine { try audioEngine.start() }
        try strobeController.start()
        setState(.running)
    }

    /// Stop the session completely. Guaranteed to leave the torch off before returning.
    /// Safe to call from any thread.
    public func stop() {
        updateTimer?.cancel()
        updateTimer = nil
        strobeController.stop()
        if audioMode == .engine { audioEngine.stop() }
        setState(.completed)
    }

    // MARK: - Private

    private func startUpdateLoop() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.setEventHandler { [weak self] in self?.tick() }
        t.schedule(
            deadline: .now(),
            repeating: 1.0 / updateHz,
            leeway: .milliseconds(2)
        )
        t.resume()
        updateTimer = t
    }

    private func tick() {
        guard !isPaused else { return }

        let elapsed = sessionElapsed

        // Natural session end.
        if elapsed >= Double(session.durationSec) {
            stop()
            onSessionEnd?()
            return
        }

        // Evaluate curves for the active segment.
        if let (_, segment) = activeSegment(at: elapsed) {
            let localTime = elapsed - segment.startSec

            let strobe = CurveEvaluator.evaluate(
                segment.strobe,
                at: localTime,
                cappedTo: session.safety.maxStrobeHz
            )
            strobeController.setParameters(
                hz:        strobe.hz,
                dutyCycle: strobe.dutyCycle,
                intensity: Float(strobe.intensity)
            )

            if audioMode == .engine {
                let binaural = CurveEvaluator.evaluate(segment.binaural, at: localTime)
                audioEngine.setParameters(
                    carrierHz:      binaural.carrierHz,
                    beatHz:         binaural.beatHz,
                    soundscapeGain: Float(binaural.gain)
                )
            }
        }

        // Path C resync: pass the audio clock's host time to the strobe timer
        // every ~5 seconds to eliminate long-term drift.
        tickCount += 1
        if audioMode == .engine && tickCount >= resyncInterval {
            tickCount = 0
            let hostTime = audioEngine.currentAudioHostTime
            if hostTime > 0 {
                strobeController.resync(toAudioHostTime: hostTime)
            }
        }
    }

    /// Linear scan for active segment — O(n) on a small list, called at 30 Hz.
    private func activeSegment(at sessionTime: Double) -> (Int, Segment)? {
        for (i, seg) in session.segments.enumerated() {
            if sessionTime >= seg.startSec && sessionTime < seg.startSec + seg.durationSec {
                return (i, seg)
            }
        }
        return nil
    }

    private func setState(_ newState: SessionRunnerState) {
        state = newState
        onStateChange?(newState)
    }
}
