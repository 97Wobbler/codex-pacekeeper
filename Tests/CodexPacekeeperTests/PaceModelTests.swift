import XCTest
@testable import CodexPacekeeperCore

final class PaceModelTests: XCTestCase {
    private let resetAt = Date(timeIntervalSince1970: 2_000)

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

    func testWeekRedlineOverridesFiveHourBehindRecommendation() {
        let recommendation = PaceRecommendation(
            primary: reading(actual: 20, recommended: 50),
            weekly: reading(actual: 91, recommended: 70)
        )

        XCTAssertEqual(recommendation.action, "Short efforts only")
        XCTAssertEqual(recommendation.status, .redline)
    }

    func testWeekThresholdAheadOverridesFiveHourBehindRecommendation() {
        let recommendation = PaceRecommendation(
            primary: reading(actual: 20, recommended: 50),
            weekly: reading(actual: 65, recommended: 40)
        )

        XCTAssertEqual(recommendation.action, "Taper recommended")
        XCTAssertEqual(recommendation.status, .threshold)
    }

    func testBothWindowsBehindRecommendPickingUpPace() {
        let recommendation = PaceRecommendation(
            primary: reading(actual: 20, recommended: 50),
            weekly: reading(actual: 35, recommended: 50)
        )

        XCTAssertEqual(recommendation.action, "Pick up pace")
        XCTAssertEqual(recommendation.status, .easy)
    }

    func testNormalWeeklyStateLetsFiveHourTempoRecommendEasingUp() {
        let recommendation = PaceRecommendation(
            primary: reading(actual: 62, recommended: 50),
            weekly: reading(actual: 50, recommended: 50)
        )

        XCTAssertEqual(recommendation.action, "Ease up soon")
        XCTAssertEqual(recommendation.status, .tempo)
    }

    func testSteadyWindowsRecommendHoldingPace() {
        let recommendation = PaceRecommendation(
            primary: reading(actual: 50, recommended: 50),
            weekly: reading(actual: 50, recommended: 50)
        )

        XCTAssertEqual(recommendation.action, "Hold this pace")
        XCTAssertEqual(recommendation.status, .steady)
    }

    private func reading(actual: Double, recommended: Double, label: String = "test") -> PaceReading {
        let delta = actual - recommended

        return PaceReading(
            label: label,
            actualPercent: actual,
            recommendedPercent: recommended,
            deltaPercentagePoints: delta,
            resetAt: resetAt,
            status: PaceStatus.status(forActualPercent: actual, deltaPercentagePoints: delta),
            isPaused: false
        )
    }
}
