import XCTest
@testable import OralableApp

final class CalibrationActiveElapsedClockTests: XCTestCase {
    func testElapsedSecondsExcludeInactiveTime() {
        var clock = CalibrationActiveElapsedClock()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        clock.reset(startingAt: start)

        XCTAssertEqual(
            clock.elapsedSeconds(now: start.addingTimeInterval(10), isActive: true),
            10
        )

        // Time spent inactive/backgrounded must not count toward calibration completion.
        XCTAssertEqual(
            clock.elapsedSeconds(now: start.addingTimeInterval(70), isActive: false),
            10
        )

        XCTAssertEqual(
            clock.elapsedSeconds(now: start.addingTimeInterval(75), isActive: true),
            10
        )
        XCTAssertEqual(
            clock.elapsedSeconds(now: start.addingTimeInterval(80), isActive: true),
            15
        )
    }
}
