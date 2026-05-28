import Foundation

// MARK: - Enumerations

public enum SessionIntent: String, Codable, Equatable, Sendable {
    case openRelax
    case alert
    case windDown
}

public enum CurveInterpolation: String, Codable, Equatable, Sendable {
    case linear
    case easeInOut
}

// MARK: - Safety

public struct SafetyProfile: Codable, Equatable, Sendable {
    /// Hard cap enforced at runtime by StrobeController regardless of session data.
    public let maxStrobeHz: Double
    public let requiresHeadphones: Bool
    /// Must be true for all light-producing sessions at v1.
    public let photosensitiveGateRequired: Bool

    public init(
        maxStrobeHz: Double,
        requiresHeadphones: Bool,
        photosensitiveGateRequired: Bool
    ) {
        self.maxStrobeHz = maxStrobeHz
        self.requiresHeadphones = requiresHeadphones
        self.photosensitiveGateRequired = photosensitiveGateRequired
    }
}

// MARK: - Strobe curve

public struct StrobeKeyframe: Codable, Equatable, Sendable {
    public let tSec: Double
    public let hz: Double
    public let dutyCycle: Double
    public let intensity: Double

    public init(tSec: Double, hz: Double, dutyCycle: Double, intensity: Double) {
        self.tSec = tSec
        self.hz = hz
        self.dutyCycle = dutyCycle
        self.intensity = intensity
    }
}

public struct StrobeCurve: Codable, Equatable, Sendable {
    public let keyframes: [StrobeKeyframe]
    public let interpolation: CurveInterpolation

    public init(keyframes: [StrobeKeyframe], interpolation: CurveInterpolation) {
        self.keyframes = keyframes
        self.interpolation = interpolation
    }
}

// MARK: - Binaural curve

public struct BinauralKeyframe: Codable, Equatable, Sendable {
    public let tSec: Double
    public let carrierHz: Double
    public let beatHz: Double
    public let gain: Double

    public init(tSec: Double, carrierHz: Double, beatHz: Double, gain: Double) {
        self.tSec = tSec
        self.carrierHz = carrierHz
        self.beatHz = beatHz
        self.gain = gain
    }
}

public struct BinauralCurve: Codable, Equatable, Sendable {
    public let keyframes: [BinauralKeyframe]
    public let interpolation: CurveInterpolation

    public init(keyframes: [BinauralKeyframe], interpolation: CurveInterpolation) {
        self.keyframes = keyframes
        self.interpolation = interpolation
    }
}

// MARK: - Segment

public struct Segment: Codable, Equatable, Sendable {
    public let startSec: Double
    public let durationSec: Double
    public let strobe: StrobeCurve
    public let binaural: BinauralCurve

    public init(
        startSec: Double,
        durationSec: Double,
        strobe: StrobeCurve,
        binaural: BinauralCurve
    ) {
        self.startSec = startSec
        self.durationSec = durationSec
        self.strobe = strobe
        self.binaural = binaural
    }
}

// MARK: - Session

public struct Session: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let intent: SessionIntent
    public let durationSec: Int
    public let safety: SafetyProfile
    /// Soundscape audio file reference (Section 9.4 open — nil until resolved).
    public let audioBedAsset: String?
    public let segments: [Segment]

    public init(
        id: String,
        title: String,
        intent: SessionIntent,
        durationSec: Int,
        safety: SafetyProfile,
        audioBedAsset: String? = nil,
        segments: [Segment]
    ) {
        self.id = id
        self.title = title
        self.intent = intent
        self.durationSec = durationSec
        self.safety = safety
        self.audioBedAsset = audioBedAsset
        self.segments = segments
    }
}
