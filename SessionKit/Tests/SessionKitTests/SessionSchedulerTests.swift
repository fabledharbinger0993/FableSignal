import XCTest
@testable import SessionKit

final class SessionSchedulerTests: XCTestCase {

    // MARK: - Empty session (no segments)

    func testEmptySession_producesOnlyStartAndEnd() {
        let session = makeSession(durationSec: 120, segments: [])
        let events = SessionScheduler.schedule(session)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].kind, .sessionStart)
        XCTAssertEqual(events[0].timeOffsetSec, 0)
        XCTAssertEqual(events[1].kind, .sessionEnd)
        XCTAssertEqual(events[1].timeOffsetSec, 120)
    }

    // MARK: - Single segment

    func testSingleSegment_producesCorrectEventCount() {
        let session = makeSession(durationSec: 600, segments: [
            makeSegment(startSec: 0, durationSec: 600),
        ])
        let events = SessionScheduler.schedule(session)
        // sessionStart + segmentBegin(0) + segmentEnd(0) + sessionEnd = 4
        XCTAssertEqual(events.count, 4)
    }

    func testSingleSegment_eventsInTimeOrder() {
        let session = makeSession(durationSec: 600, segments: [
            makeSegment(startSec: 0, durationSec: 600),
        ])
        let events = SessionScheduler.schedule(session)
        XCTAssertEqual(events[0].kind, .sessionStart)
        XCTAssertEqual(events[0].timeOffsetSec, 0)
        XCTAssertEqual(events[1].kind, .segmentBegin(segmentIndex: 0))
        XCTAssertEqual(events[1].timeOffsetSec, 0)
        XCTAssertEqual(events[2].kind, .segmentEnd(segmentIndex: 0))
        XCTAssertEqual(events[2].timeOffsetSec, 600)
        XCTAssertEqual(events[3].kind, .sessionEnd)
        XCTAssertEqual(events[3].timeOffsetSec, 600)
    }

    // MARK: - Multiple segments

    func testMultipleSegments_allEventsPresent() {
        let session = makeSession(durationSec: 1800, segments: [
            makeSegment(startSec:    0, durationSec: 600),
            makeSegment(startSec:  600, durationSec: 600),
            makeSegment(startSec: 1200, durationSec: 600),
        ])
        let events = SessionScheduler.schedule(session)
        // sessionStart + 3*(segmentBegin+segmentEnd) + sessionEnd = 8
        XCTAssertEqual(events.count, 8)
    }

    func testMultipleSegments_eventTimesCorrect() {
        let session = makeSession(durationSec: 900, segments: [
            makeSegment(startSec:   0, durationSec: 300),
            makeSegment(startSec: 300, durationSec: 300),
            makeSegment(startSec: 600, durationSec: 300),
        ])
        let events = SessionScheduler.schedule(session)
        let times = events.map { $0.timeOffsetSec }
        XCTAssertEqual(times, [0, 0, 300, 300, 600, 600, 900, 900])
    }

    func testMultipleSegments_segmentIndicesCorrect() {
        let session = makeSession(durationSec: 900, segments: [
            makeSegment(startSec:   0, durationSec: 300),
            makeSegment(startSec: 300, durationSec: 300),
            makeSegment(startSec: 600, durationSec: 300),
        ])
        let events = SessionScheduler.schedule(session)
        let begins = events.filter {
            if case .segmentBegin = $0.kind { return true }
            return false
        }
        let ends = events.filter {
            if case .segmentEnd = $0.kind { return true }
            return false
        }
        XCTAssertEqual(begins.count, 3)
        XCTAssertEqual(ends.count, 3)
        XCTAssertEqual(begins[0].kind, .segmentBegin(segmentIndex: 0))
        XCTAssertEqual(begins[1].kind, .segmentBegin(segmentIndex: 1))
        XCTAssertEqual(begins[2].kind, .segmentBegin(segmentIndex: 2))
        XCTAssertEqual(ends[0].kind, .segmentEnd(segmentIndex: 0))
        XCTAssertEqual(ends[1].kind, .segmentEnd(segmentIndex: 1))
        XCTAssertEqual(ends[2].kind, .segmentEnd(segmentIndex: 2))
    }

    // MARK: - Tiebreak ordering at equal timestamps

    func testTiebreak_sessionStartBeforeSegmentBeginAtT0() {
        let session = makeSession(durationSec: 300, segments: [
            makeSegment(startSec: 0, durationSec: 300),
        ])
        let events = SessionScheduler.schedule(session)
        let t0 = events.filter { $0.timeOffsetSec == 0 }
        XCTAssertEqual(t0.count, 2)
        XCTAssertEqual(t0[0].kind, .sessionStart)
        XCTAssertEqual(t0[1].kind, .segmentBegin(segmentIndex: 0))
    }

    func testTiebreak_segmentEndBeforeSessionEndAtFinalTime() {
        let session = makeSession(durationSec: 300, segments: [
            makeSegment(startSec: 0, durationSec: 300),
        ])
        let events = SessionScheduler.schedule(session)
        let tEnd = events.filter { $0.timeOffsetSec == 300 }
        XCTAssertEqual(tEnd.count, 2)
        XCTAssertEqual(tEnd[0].kind, .segmentEnd(segmentIndex: 0))
        XCTAssertEqual(tEnd[1].kind, .sessionEnd)
    }

    func testTiebreak_segmentEndBeforeNextSegmentBeginAtBoundary() {
        // Segment 0 ends at t=300; segment 1 begins at t=300
        let session = makeSession(durationSec: 600, segments: [
            makeSegment(startSec:   0, durationSec: 300),
            makeSegment(startSec: 300, durationSec: 300),
        ])
        let events = SessionScheduler.schedule(session)
        let tBoundary = events.filter { $0.timeOffsetSec == 300 }
        XCTAssertEqual(tBoundary.count, 2)
        XCTAssertEqual(tBoundary[0].kind, .segmentEnd(segmentIndex: 0))
        XCTAssertEqual(tBoundary[1].kind, .segmentBegin(segmentIndex: 1))
    }

    // MARK: - Output is sorted

    func testOutputIsNonDecreasingByTime() {
        let session = makeSession(durationSec: 1800, segments: [
            makeSegment(startSec:    0, durationSec:  600),
            makeSegment(startSec:  600, durationSec:  600),
            makeSegment(startSec: 1200, durationSec:  600),
        ])
        let events = SessionScheduler.schedule(session)
        for i in 1..<events.count {
            XCTAssertLessThanOrEqual(
                events[i - 1].timeOffsetSec,
                events[i].timeOffsetSec,
                "Event at index \(i-1) should come before event at index \(i)"
            )
        }
    }

    // MARK: - Session duration boundary

    func testSessionEnd_timeMatchesDurationSec() {
        let session = makeSession(durationSec: 900, segments: [])
        let events = SessionScheduler.schedule(session)
        let end = events.last!
        XCTAssertEqual(end.kind, .sessionEnd)
        XCTAssertEqual(end.timeOffsetSec, 900)
    }

    // MARK: - Wind-down session structure (three segments, stepped descent)

    func testWindDownSession_threeSegments_correctStructure() {
        // Matches the brief's wind-down: 8→5→3 Hz stepped, three segments
        let session = makeSession(durationSec: 1200, segments: [
            makeSegment(startSec:   0, durationSec: 400),
            makeSegment(startSec: 400, durationSec: 400),
            makeSegment(startSec: 800, durationSec: 400),
        ])
        let events = SessionScheduler.schedule(session)
        XCTAssertEqual(events.count, 8) // 2 + 3*2
        XCTAssertEqual(events.first!.kind, .sessionStart)
        XCTAssertEqual(events.last!.kind,  .sessionEnd)
        XCTAssertEqual(events.last!.timeOffsetSec, 1200)
    }

    // MARK: - Helpers

    private func makeSession(durationSec: Int, segments: [Segment]) -> Session {
        Session(
            id: "test-session",
            title: "Test",
            intent: .openRelax,
            durationSec: durationSec,
            safety: SafetyProfile(
                maxStrobeHz: 50,
                requiresHeadphones: true,
                photosensitiveGateRequired: true
            ),
            segments: segments
        )
    }

    private func makeSegment(startSec: Double, durationSec: Double) -> Segment {
        let strobe = StrobeCurve(
            keyframes: [StrobeKeyframe(tSec: startSec, hz: 10, dutyCycle: 0.5, intensity: 0.6)],
            interpolation: .linear
        )
        let binaural = BinauralCurve(
            keyframes: [BinauralKeyframe(tSec: startSec, carrierHz: 200, beatHz: 10, gain: 0.8)],
            interpolation: .linear
        )
        return Segment(startSec: startSec, durationSec: durationSec, strobe: strobe, binaural: binaural)
    }
}
