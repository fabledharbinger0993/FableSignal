import XCTest
@testable import SessionKit

final class SessionModelTests: XCTestCase {

    // MARK: - SessionIntent round-trip

    func testSessionIntentEncodesAllCases() throws {
        let cases: [(SessionIntent, String)] = [
            (.openRelax, "openRelax"),
            (.alert,     "alert"),
            (.windDown,  "windDown"),
        ]
        for (intent, raw) in cases {
            let data = try JSONEncoder().encode(intent)
            let decoded = String(data: data, encoding: .utf8)!
            XCTAssertEqual(decoded, "\"\(raw)\"", "Intent \(intent) should encode to \"\(raw)\"")
            let roundTripped = try JSONDecoder().decode(SessionIntent.self, from: data)
            XCTAssertEqual(roundTripped, intent)
        }
    }

    // MARK: - CurveInterpolation round-trip

    func testCurveInterpolationEncodesAllCases() throws {
        let cases: [(CurveInterpolation, String)] = [
            (.linear,    "linear"),
            (.easeInOut, "easeInOut"),
        ]
        for (interp, raw) in cases {
            let data = try JSONEncoder().encode(interp)
            let decoded = String(data: data, encoding: .utf8)!
            XCTAssertEqual(decoded, "\"\(raw)\"")
            let roundTripped = try JSONDecoder().decode(CurveInterpolation.self, from: data)
            XCTAssertEqual(roundTripped, interp)
        }
    }

    // MARK: - SafetyProfile round-trip

    func testSafetyProfileRoundTrip() throws {
        let profile = SafetyProfile(
            maxStrobeHz: 50.0,
            requiresHeadphones: true,
            photosensitiveGateRequired: true
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(SafetyProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
    }

    // MARK: - StrobeCurve round-trip

    func testStrobeCurveRoundTrip() throws {
        let curve = StrobeCurve(
            keyframes: [
                StrobeKeyframe(tSec: 0, hz: 10, dutyCycle: 0.5, intensity: 0.6),
                StrobeKeyframe(tSec: 60, hz: 6, dutyCycle: 0.5, intensity: 0.6),
            ],
            interpolation: .easeInOut
        )
        let data = try JSONEncoder().encode(curve)
        let decoded = try JSONDecoder().decode(StrobeCurve.self, from: data)
        XCTAssertEqual(decoded, curve)
    }

    // MARK: - BinauralCurve round-trip

    func testBinauralCurveRoundTrip() throws {
        let curve = BinauralCurve(
            keyframes: [
                BinauralKeyframe(tSec: 0,  carrierHz: 200, beatHz: 10, gain: 0.8),
                BinauralKeyframe(tSec: 60, carrierHz: 200, beatHz:  6, gain: 0.8),
            ],
            interpolation: .linear
        )
        let data = try JSONEncoder().encode(curve)
        let decoded = try JSONDecoder().decode(BinauralCurve.self, from: data)
        XCTAssertEqual(decoded, curve)
    }

    // MARK: - Session round-trip

    func testSessionRoundTripWithAudioBedAsset() throws {
        let session = makeOpenRelaxSession(audioBedAsset: "rain_loop.caf")
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)
        XCTAssertEqual(decoded, session)
        XCTAssertEqual(decoded.audioBedAsset, "rain_loop.caf")
    }

    func testSessionRoundTripWithoutAudioBedAsset() throws {
        let session = makeOpenRelaxSession(audioBedAsset: nil)
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)
        XCTAssertEqual(decoded, session)
        XCTAssertNil(decoded.audioBedAsset)
    }

    func testSessionDecodesFromRawJSON() throws {
        let json = """
        {
            "id": "open-relax-v1",
            "title": "Open / Relax",
            "intent": "openRelax",
            "durationSec": 600,
            "safety": {
                "maxStrobeHz": 15.0,
                "requiresHeadphones": true,
                "photosensitiveGateRequired": true
            },
            "segments": [
                {
                    "startSec": 0.0,
                    "durationSec": 600.0,
                    "strobe": {
                        "keyframes": [
                            { "tSec": 0.0,   "hz": 10.0, "dutyCycle": 0.5, "intensity": 0.6 },
                            { "tSec": 600.0, "hz":  6.0, "dutyCycle": 0.5, "intensity": 0.6 }
                        ],
                        "interpolation": "easeInOut"
                    },
                    "binaural": {
                        "keyframes": [
                            { "tSec": 0.0,   "carrierHz": 200.0, "beatHz": 10.0, "gain": 0.8 },
                            { "tSec": 600.0, "carrierHz": 200.0, "beatHz":  6.0, "gain": 0.8 }
                        ],
                        "interpolation": "easeInOut"
                    }
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let session = try JSONDecoder().decode(Session.self, from: data)
        XCTAssertEqual(session.id, "open-relax-v1")
        XCTAssertEqual(session.intent, .openRelax)
        XCTAssertEqual(session.durationSec, 600)
        XCTAssertEqual(session.safety.maxStrobeHz, 15.0)
        XCTAssertTrue(session.safety.photosensitiveGateRequired)
        XCTAssertNil(session.audioBedAsset)
        XCTAssertEqual(session.segments.count, 1)
        XCTAssertEqual(session.segments[0].strobe.keyframes[1].hz, 6.0)
        XCTAssertEqual(session.segments[0].binaural.keyframes[0].beatHz, 10.0)
    }

    // MARK: - Helpers

    private func makeOpenRelaxSession(audioBedAsset: String?) -> Session {
        let strobe = StrobeCurve(
            keyframes: [
                StrobeKeyframe(tSec: 0,   hz: 10, dutyCycle: 0.5, intensity: 0.6),
                StrobeKeyframe(tSec: 600, hz: 6,  dutyCycle: 0.5, intensity: 0.6),
            ],
            interpolation: .easeInOut
        )
        let binaural = BinauralCurve(
            keyframes: [
                BinauralKeyframe(tSec: 0,   carrierHz: 200, beatHz: 10, gain: 0.8),
                BinauralKeyframe(tSec: 600, carrierHz: 200, beatHz:  6, gain: 0.8),
            ],
            interpolation: .easeInOut
        )
        return Session(
            id: "open-relax-v1",
            title: "Open / Relax",
            intent: .openRelax,
            durationSec: 600,
            safety: SafetyProfile(
                maxStrobeHz: 15.0,
                requiresHeadphones: true,
                photosensitiveGateRequired: true
            ),
            audioBedAsset: audioBedAsset,
            segments: [
                Segment(startSec: 0, durationSec: 600, strobe: strobe, binaural: binaural),
            ]
        )
    }
}
