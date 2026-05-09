import XCTest
@testable import CodexPacekeeperCore

final class PaceModelTests: XCTestCase {
    func testRecommendedPaceUsesElapsedWindowTime() {
        let now = Date(timeIntervalSince1970: 1_000)
        let resetAt = now.addingTimeInterval(100)
        let window = UsageWindow(
            label: "5h",
            usedPercent: 42,
            resetAt: resetAt,
            limitWindowSeconds: 200
        )

        let reading = window.pace(at: now)

        XCTAssertEqual(reading.recommendedPercent, 50, accuracy: 0.0001)
        XCTAssertEqual(reading.deltaPercentagePoints, -8, accuracy: 0.0001)
        XCTAssertEqual(reading.status, .steady)
    }

    func testPaceStatusThresholds() {
        XCTAssertEqual(PaceStatus.status(forActualPercent: 10, deltaPercentagePoints: -10), .easy)
        XCTAssertEqual(PaceStatus.status(forActualPercent: 20, deltaPercentagePoints: 10), .steady)
        XCTAssertEqual(PaceStatus.status(forActualPercent: 30, deltaPercentagePoints: 11), .tempo)
        XCTAssertEqual(PaceStatus.status(forActualPercent: 45, deltaPercentagePoints: 21), .threshold)
        XCTAssertEqual(PaceStatus.status(forActualPercent: 55, deltaPercentagePoints: 36), .redline)
        XCTAssertEqual(PaceStatus.status(forActualPercent: 90, deltaPercentagePoints: 0), .redline)
    }

    func testPercentInputsAreClamped() {
        let now = Date(timeIntervalSince1970: 1_000)
        let resetAt = now.addingTimeInterval(100)
        let window = UsageWindow(
            label: "5h",
            usedPercent: 140,
            resetAt: resetAt,
            limitWindowSeconds: 200
        )

        let reading = window.pace(at: now)

        XCTAssertEqual(reading.actualPercent, 100)
        XCTAssertEqual(reading.status, .redline)
    }
}
