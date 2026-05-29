// UNVERIFIED — requires device test. AVCaptureDevice torch is unavailable in simulator.
import AVFoundation

// MARK: - Errors

public enum StrobeError: Error, Equatable {
    /// The device has no torch (e.g., iPod touch, Mac, or torch locked by another process).
    case torchUnavailable
    /// `AVCaptureDevice.lockForConfiguration()` threw — another process holds the camera.
    case lockFailed
}

// MARK: - StrobeController

/// Drives the device torch as a stroboscopic light source.
///
/// Timing model (Path C):
///   - A single `DispatchSourceTimer` on a `.userInteractive` private queue fires
///     alternately for the "on" and "off" phases of each strobe cycle.
///   - The per-phase interval is computed from the current Hz and duty cycle, giving
///     true duty-cycle control without a second timer.
///   - Long-term drift relative to the audio engine is eliminated in Phase 4 via
///     `resync(toAudioHostTime:)`, which nudges the next deadline by the measured offset.
///
/// Safety cap: `maxStrobeHz` is enforced in `setParameters` (defense-in-depth) and
/// again at the start of each timer fire. A malformed session or concurrent parameter
/// update can never cause the torch to strobe above the cap.
///
/// Threading model:
///   - `start()`, `stop()`, `setParameters()` — call from the session/main thread.
///   - Timer callback (`timerFired()`) — runs on the private `timerQueue`.
///   - Cross-thread reads of `target*` properties use aligned Double/Float stores,
///     which are hardware-atomic on ARM64. Worst-case stale read: one strobe cycle.
///   - `isRunning` is checked at both the top of `timerFired()` and inside `setTorch()`;
///     this double-guard minimises the window in which a late timer fire could access
///     the torch after `stop()` has released the lock.
public final class StrobeController {

    // MARK: - Public

    public let maxStrobeHz: Double

    public private(set) var isRunning = false

    /// The Hz value in effect after applying the `maxStrobeHz` cap.
    public private(set) var effectiveHz: Double = 0

    /// Called on the main thread when thermal pressure forces an emergency shutdown.
    /// The session layer must call `stop()` in response.
    public var onThermalShutdown: (() -> Void)?

    // MARK: - Private — session thread

    private var device: AVCaptureDevice?
    private var timer: DispatchSourceTimer?

    // MARK: - Private — cross-thread (ARM64 aligned r/w; see threading note above)

    private var targetHz: Double       = 0
    private var targetDutyCycle: Double = 0.5
    private var targetIntensity: Float  = 0.6

    // MARK: - Private — timer-queue-only

    private var strobeIsOn = false
    private let timerQueue = DispatchQueue(
        label: "com.fablesignal.strobe",
        qos: .userInteractive
    )

    // MARK: - Init

    public init(maxStrobeHz: Double) {
        self.maxStrobeHz = maxStrobeHz
    }

    // MARK: - Session-thread API

    /// Update strobe parameters. The `maxStrobeHz` cap is applied immediately and
    /// reflected in `effectiveHz`. Changes take effect on the next timer phase boundary.
    public func setParameters(hz: Double, dutyCycle: Double, intensity: Float) {
        let capped = min(hz, maxStrobeHz)
        targetHz        = capped
        targetDutyCycle = max(0.01, min(1.0, dutyCycle))
        targetIntensity = max(0.0,  min(1.0, intensity))
        effectiveHz     = capped
    }

    /// Acquire the torch hardware lock and begin strobing.
    ///
    /// - Throws: `StrobeError.torchUnavailable` if no torch exists on this device.
    ///           `StrobeError.lockFailed` if the camera is in use by another process.
    public func start() throws {
        let d = try acquireDevice()
        device    = d
        isRunning = true
        startTimer()
    }

    /// Stop strobing, force the torch off, and release the hardware lock.
    ///
    /// Guaranteed to leave the torch off before returning. Safe to call during an
    /// interruption (phone call, audio route change) from any thread, though the
    /// session layer should always call from a consistent thread to avoid data races
    /// on `device` and `isRunning`.
    public func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
        // Torch off while the lock is still held.
        device?.torchMode = .off
        device?.unlockForConfiguration()
        device = nil
    }

    /// Phase 4 — resync the strobe timer to the audio engine's render clock.
    ///
    /// `hostTime` is the `mHostTime` value from an `AVAudioTime` at a known strobe
    /// phase boundary. The implementation computes the drift between the audio clock's
    /// current phase within the strobe period and the timer's phase, then nudges the
    /// next scheduled deadline by that offset.
    public func resync(toAudioHostTime hostTime: UInt64) {
        // Phase 4 implementation placeholder.
        // Steps:
        // 1. Convert hostTime to seconds via mach_timebase_info.
        // 2. Compute elapsed time since cycle start in audio-clock coordinates.
        // 3. Compute offset = (elapsed % period) - timerPhaseElapsed.
        // 4. Reschedule timer deadline by +offset (clamped to [-period/2, +period/2]).
    }

    // MARK: - Private helpers

    private func acquireDevice() throws -> AVCaptureDevice {
        guard let d = AVCaptureDevice.default(for: .video), d.hasTorch else {
            throw StrobeError.torchUnavailable
        }
        do {
            try d.lockForConfiguration()
        } catch {
            throw StrobeError.lockFailed
        }
        return d
    }

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: timerQueue)
        t.setEventHandler { [weak self] in self?.timerFired() }
        // Fire immediately so the first on-cycle begins without visible delay.
        t.schedule(deadline: .now(), leeway: .microseconds(200))
        t.resume()
        timer = t
    }

    // Runs on timerQueue — must be allocation-free and non-blocking.
    private func timerFired() {
        guard isRunning else { return }

        // Thermal guard — cheap property read, checked once per strobe half-cycle.
        var effectiveIntensity = targetIntensity
        switch ProcessInfo.processInfo.thermalState {
        case .nominal, .fair:
            break
        case .serious:
            // Degrade intensity to reduce LED heat load.
            effectiveIntensity = min(targetIntensity, 0.4)
        case .critical:
            // Emergency torch-off from the timer queue; delegate full stop to session layer.
            device?.torchMode = .off
            isRunning = false
            DispatchQueue.main.async { [weak self] in self?.onThermalShutdown?() }
            return
        @unknown default:
            break
        }

        // Apply the runtime cap a second time (defence-in-depth for concurrent updates).
        let hz        = min(max(targetHz, 0.1), maxStrobeHz)
        let dutyCycle = targetDutyCycle

        strobeIsOn.toggle()
        setTorch(strobeIsOn, intensity: effectiveIntensity)

        // Schedule the next phase transition at the correct duty-cycle interval.
        let periodNs = Int(1e9 / hz)
        let delayNs  = strobeIsOn
            ? Int(Double(periodNs) * dutyCycle)          // on → schedule turn-off
            : Int(Double(periodNs) * (1.0 - dutyCycle))  // off → schedule turn-on

        timer?.schedule(
            deadline: .now() + .nanoseconds(max(delayNs, 1_000)),
            leeway: .microseconds(200)
        )
    }

    private func setTorch(_ on: Bool, intensity: Float) {
        // Double-check isRunning: stop() may have fired between timerFired()'s
        // guard and this call, releasing the lock. Operating the torch without
        // the lock held produces an AVFoundation error; the catch below handles it.
        guard isRunning, let device = device else { return }
        do {
            if on {
                try device.setTorchModeOn(level: intensity)
            } else {
                device.torchMode = .off
            }
        } catch {
            // Lock lost mid-session (rare; another process took the camera).
            // Mark stopped; session layer will receive the next interruption callback.
            isRunning = false
        }
    }
}
