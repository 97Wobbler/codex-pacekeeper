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
        XCTAssertEqual(PaceStatus.status(forActualPercent: 10, deltaPercentagePoints: -10), .steady)
        XCTAssertEqual(PaceStatus.status(forActualPercent: 20, deltaPercentagePoints: 10), .steady)
        XCTAssertEqual(PaceStatus.status(forActualPercent: 30, deltaPercentagePoints: 11), .tempo)
        XCTAssertEqual(PaceStatus.status(forActualPercent: 30, deltaPercentagePoints: -11), .tempo)
        XCTAssertEqual(PaceStatus.status(forActualPercent: 45, deltaPercentagePoints: 21), .threshold)
        XCTAssertEqual(PaceStatus.status(forActualPercent: 45, deltaPercentagePoints: -21), .threshold)
        XCTAssertEqual(PaceStatus.status(forActualPercent: 55, deltaPercentagePoints: 36), .redline)
        XCTAssertEqual(PaceStatus.status(forActualPercent: 55, deltaPercentagePoints: -36), .redline)
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
        XCTAssertEqual(recommendation.direction, .slowDown)
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
            primary: reading(actual: 38, recommended: 50),
            weekly: reading(actual: 38, recommended: 50)
        )

        XCTAssertEqual(recommendation.action, "Pick up pace")
        XCTAssertEqual(recommendation.status, .tempo)
        XCTAssertEqual(recommendation.direction, .speedUp)
    }

    func testFarBehindTargetEscalatesRecommendationSeverity() {
        let recommendation = PaceRecommendation(
            primary: reading(actual: 10, recommended: 50),
            weekly: reading(actual: 10, recommended: 50)
        )

        XCTAssertEqual(recommendation.action, "Use more now")
        XCTAssertEqual(recommendation.status, .redline)
        XCTAssertEqual(recommendation.direction, .speedUp)
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
        XCTAssertEqual(recommendation.direction, .hold)
    }

    func testRecentTrendCalculatesPercentPointsPerHour() {
        let now = Date(timeIntervalSince1970: 10_000)
        let primaryResetAt = now.addingTimeInterval(5 * 60 * 60)
        let weeklyResetAt = now.addingTimeInterval(7 * 24 * 60 * 60)
        let samples = [
            usageSample(
                timestamp: now.addingTimeInterval(-30 * 60),
                primaryUsedPercent: 10,
                primaryResetAt: primaryResetAt,
                weeklyUsedPercent: 40,
                weeklyResetAt: weeklyResetAt
            ),
            usageSample(
                timestamp: now,
                primaryUsedPercent: 16,
                primaryResetAt: primaryResetAt,
                weeklyUsedPercent: 41,
                weeklyResetAt: weeklyResetAt
            )
        ]

        let trend = UsageHistoryStore.recentTrend(samples: samples, now: now)

        XCTAssertEqual(trend?.primaryPercentPointsPerHour, 12, accuracy: 0.0001)
        XCTAssertEqual(trend?.weeklyPercentPointsPerHour, 2, accuracy: 0.0001)
        XCTAssertEqual(trend?.sampleCount, 2)
        XCTAssertEqual(trend?.interval, 30 * 60, accuracy: 0.0001)
    }

    func testRecentTrendIgnoresSamplesAcrossResetBoundary() {
        let now = Date(timeIntervalSince1970: 10_000)
        let latestPrimaryResetAt = now.addingTimeInterval(5 * 60 * 60)
        let latestWeeklyResetAt = now.addingTimeInterval(7 * 24 * 60 * 60)
        let oldPrimaryResetAt = now.addingTimeInterval(4 * 60 * 60)
        let samples = [
            usageSample(
                timestamp: now.addingTimeInterval(-45 * 60),
                primaryUsedPercent: 90,
                primaryResetAt: oldPrimaryResetAt,
                weeklyUsedPercent: 70,
                weeklyResetAt: latestWeeklyResetAt
            ),
            usageSample(
                timestamp: now.addingTimeInterval(-30 * 60),
                primaryUsedPercent: 10,
                primaryResetAt: latestPrimaryResetAt,
                weeklyUsedPercent: 40,
                weeklyResetAt: latestWeeklyResetAt
            ),
            usageSample(
                timestamp: now,
                primaryUsedPercent: 16,
                primaryResetAt: latestPrimaryResetAt,
                weeklyUsedPercent: 41,
                weeklyResetAt: latestWeeklyResetAt
            )
        ]

        let trend = UsageHistoryStore.recentTrend(samples: samples, now: now)

        XCTAssertEqual(trend?.primaryPercentPointsPerHour, 12, accuracy: 0.0001)
        XCTAssertEqual(trend?.weeklyPercentPointsPerHour, 2, accuracy: 0.0001)
        XCTAssertEqual(trend?.sampleCount, 2)
    }

    func testRecentTrendReturnsNilWhenHistoryIsInsufficient() {
        let now = Date(timeIntervalSince1970: 10_000)
        let samples = [
            usageSample(
                timestamp: now,
                primaryUsedPercent: 10,
                primaryResetAt: now.addingTimeInterval(5 * 60 * 60),
                weeklyUsedPercent: 40,
                weeklyResetAt: now.addingTimeInterval(7 * 24 * 60 * 60)
            )
        ]

        XCTAssertNil(UsageHistoryStore.recentTrend(samples: samples, now: now))
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

    private func usageSample(
        timestamp: Date,
        primaryUsedPercent: Double,
        primaryResetAt: Date,
        weeklyUsedPercent: Double,
        weeklyResetAt: Date
    ) -> UsageSample {
        UsageSample(
            timestamp: timestamp,
            primaryUsedPercent: primaryUsedPercent,
            primaryResetAt: primaryResetAt,
            weeklyUsedPercent: weeklyUsedPercent,
            weeklyResetAt: weeklyResetAt
        )
    }
}
