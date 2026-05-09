import CodexPacekeeperCore
import Foundation

enum DemoUsageSnapshots {
    static func make(now: Date = Date()) -> [UsageSnapshot] {
        [
            snapshot(
                now: now,
                primary: reading(now: now, label: "5h", actual: 15, target: 68, resetAfter: 53 * 60),
                weekly: reading(now: now, label: "week", actual: 20, target: 60, resetAfter: 2 * 24 * 60 * 60 + 17 * 60 * 60)
            ),
            snapshot(
                now: now,
                primary: reading(now: now, label: "5h", actual: 45, target: 58, resetAfter: 2 * 60 * 60 + 6 * 60),
                weekly: reading(now: now, label: "week", actual: 42, target: 55, resetAfter: 3 * 24 * 60 * 60 + 4 * 60 * 60)
            ),
            snapshot(
                now: now,
                primary: reading(now: now, label: "5h", actual: 52, target: 50, resetAfter: 2 * 60 * 60 + 30 * 60),
                weekly: reading(now: now, label: "week", actual: 51, target: 50, resetAfter: 3 * 24 * 60 * 60 + 12 * 60 * 60)
            ),
            snapshot(
                now: now,
                primary: reading(now: now, label: "5h", actual: 68, target: 50, resetAfter: 2 * 60 * 60 + 30 * 60),
                weekly: reading(now: now, label: "week", actual: 52, target: 50, resetAfter: 3 * 24 * 60 * 60 + 12 * 60 * 60)
            ),
            snapshot(
                now: now,
                primary: reading(now: now, label: "5h", actual: 0, target: 50, resetAfter: 2 * 60 * 60 + 30 * 60),
                weekly: reading(now: now, label: "week", actual: 99, target: 57, resetAfter: 3 * 24 * 60 * 60)
            )
        ]
    }

    private static func snapshot(now: Date, primary: PaceReading, weekly: PaceReading) -> UsageSnapshot {
        UsageSnapshot(
            primary: primary,
            weekly: weekly,
            lastRefreshedAt: now,
            state: .fresh,
            message: nil
        )
    }

    private static func reading(
        now: Date,
        label: String,
        actual: Double,
        target: Double,
        resetAfter: TimeInterval
    ) -> PaceReading {
        let delta = actual - target
        let windowSeconds: TimeInterval = label == "5h" ? 5 * 60 * 60 : 7 * 24 * 60 * 60

        return PaceReading(
            label: label,
            actualPercent: actual,
            recommendedPercent: target,
            deltaPercentagePoints: delta,
            resetAt: now.addingTimeInterval(resetAfter),
            limitWindowSeconds: windowSeconds,
            status: PaceStatus.status(forActualPercent: actual, deltaPercentagePoints: delta),
            isPaused: false
        )
    }
}
