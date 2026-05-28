// MARK: - Event model

public enum ScheduledEventKind: Equatable, Sendable {
    case sessionStart
    case segmentBegin(segmentIndex: Int)
    case segmentEnd(segmentIndex: Int)
    case sessionEnd
}

public struct ScheduledEvent: Equatable, Sendable {
    public let timeOffsetSec: Double
    public let kind: ScheduledEventKind

    public init(timeOffsetSec: Double, kind: ScheduledEventKind) {
        self.timeOffsetSec = timeOffsetSec
        self.kind = kind
    }
}

// MARK: - Scheduler

/// Converts a Session into a time-ordered sequence of lifecycle events.
///
/// SessionRunner consumes this stream to drive audio and strobe transitions.
/// CurveEvaluator handles continuous interpolation between events in real time.
public enum SessionScheduler {

    public static func schedule(_ session: Session) -> [ScheduledEvent] {
        var events: [ScheduledEvent] = []
        events.reserveCapacity(session.segments.count * 2 + 2)

        events.append(ScheduledEvent(timeOffsetSec: 0, kind: .sessionStart))

        for (index, segment) in session.segments.enumerated() {
            events.append(ScheduledEvent(
                timeOffsetSec: segment.startSec,
                kind: .segmentBegin(segmentIndex: index)
            ))
            events.append(ScheduledEvent(
                timeOffsetSec: segment.startSec + segment.durationSec,
                kind: .segmentEnd(segmentIndex: index)
            ))
        }

        events.append(ScheduledEvent(
            timeOffsetSec: Double(session.durationSec),
            kind: .sessionEnd
        ))

        events.sort { lhs, rhs in
            if lhs.timeOffsetSec != rhs.timeOffsetSec {
                return lhs.timeOffsetSec < rhs.timeOffsetSec
            }
            return kindSortOrder(lhs.kind) < kindSortOrder(rhs.kind)
        }

        return events
    }

    /// Tiebreak order for events at the same timestamp:
    /// sessionStart < segmentEnd < segmentBegin < sessionEnd
    /// segmentEnd before segmentBegin so a prior segment fully closes before the next opens.
    private static func kindSortOrder(_ kind: ScheduledEventKind) -> Int {
        switch kind {
        case .sessionStart:       return 0
        case .segmentEnd:         return 1
        case .segmentBegin:       return 2
        case .sessionEnd:         return 3
        }
    }
}
