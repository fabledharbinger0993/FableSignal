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

    // MARK: - Private — resync state

    private var startMachTime: UInt64 = 0

    // Mach-tick → nanosecond ratio, cached once. On iOS devices numer==denom==1
    // (mach time is already in ns), but computed correctly for portability.
    private let machToNs: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

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
        device        = d
        isRunning     = true
        startMachTime = mach_absolute_time()
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

    /// Resync the strobe timer to the audio engine's render clock (Path C).
    ///
    /// `hostTime` is `AVAudioNode.lastRenderTime.hostTime` — the mach absolute time of
    /// the most recent audio render cycle, supplied by `SessionRunner` every ~5 s.
    ///
    /// Algorithm:
    ///   1. Compute elapsed time since strobe start in audio-clock nanoseconds.
    ///   2. Locate the current phase within the strobe period.
    ///   3. Determine time remaining until the next phase transition.
    ///   4. Reschedule the timer from now so it fires exactly at that transition,
    ///      correcting any drift that accumulated between the two independent clocks.
    public func resync(toAudioHostTime hostTime: UInt64) {
        guard isRunning, hostTime > 0, startMachTime > 0 else { return }

        let hz        = max(min(targetHz, maxStrobeHz), 0.1)
        let periodNs  = 1e9 / hz
        let ratio     = machToNs

        // Elapsed nanoseconds since strobe start, measured on the audio clock.
        let elapsedMach = hostTime >= startMachTime ? hostTime - startMachTime : 0
        let elapsedNs   = Double(elapsedMach) * ratio

        // Phase within the current period [0, periodNs).
        let phaseNs     = elapsedNs.truncatingRemainder(dividingBy: periodNs)
        let dutyCycleNs = periodNs * targetDutyCycle

        // Expected strobe state and nanoseconds until the next transition.
        let expectedOn         = phaseNs < dutyCycleNs
        let nsUntilTransition  = expectedOn
            ? dutyCycleNs - phaseNs   // on → time until turn-off
            : periodNs    - phaseNs   // off → time until turn-on

        // Reschedule timer from now (audio hostTime ≈ now within one render buffer).
        timer?.schedule(
            deadline: .now() + .nanoseconds(max(Int(nsUntilTransition), 1_000)),
            leeway: .microseconds(200)
        )

        // Bring the phase flag into agreement with the expected state.
        let on = expectedOn
        timerQueue.async { [weak self] in self?.strobeIsOn = on }
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
