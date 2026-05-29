// AudioEngine is device-only (AVFoundation, no simulator support).
// These tests serve as a compilation gate only — they verify the module compiles
// and public interfaces exist, but make no assertions about audio behavior.
//
// UNVERIFIED hardware behaviors (require physical iOS device):
//   - Clean binaural beat perceived at 6 / 10 / 18 Hz through headphones
//   - Click-free frequency transitions across segment boundaries
//   - No audible artifacts at session start/stop
//   - Pink noise soundscape does not mask 200–500 Hz binaural carrier band
//   - Engine survives audio route change (headphones unplugged mid-session)
//
// Run on device: start a session, confirm perceived beat matches target beat Hz.

import XCTest
@testable import AudioEngine

final class AudioEngineTests: XCTestCase {

    func testAudioEngineControllerInstantiates() {
        // Verify the public type exists and can be created without crashing.
        // Does NOT start the engine (AVAudioEngine requires a real audio device).
        let controller = AudioEngineController()
        XCTAssertFalse(controller.isRunning)
    }

    func testAudioEngineControllerAcceptsAudioBedAssetParam() {
        // Verifies the audioBedAsset seam compiles (Section 9.4 — future FileSoundscapeMixer).
        let controller = AudioEngineController(audioBedAsset: "ambient.caf")
        XCTAssertFalse(controller.isRunning)
    }
}
