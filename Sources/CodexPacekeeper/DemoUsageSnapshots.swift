import CodexPacekeeperCore
import Foundation

enum DemoUsageSnapshots {
    static func make(now: Date = Date()) -> [UsageDashboardSnapshot] {
        let snapshots = [
            (
                UsageProvider.codex,
                snapshot(
                    now: now,
                    primary: reading(now: now, label: "5h", actual: 15, target: 68, resetAfter: 53 * 60),
                    weekly: reading(now: now, label: "week", actual: 20, target: 60, resetAfter: 2 * 24 * 60 * 60 + 17 * 60 * 60)
                )
            ),
            (
                UsageProvider.claudeCode,
                snapshot(
                    now: now,
                    primary: reading(now: now, label: "5h", actual: 45, target: 58, resetAfter: 2 * 60 * 60 + 6 * 60),
                    weekly: reading(now: now, label: "week", actual: 42, target: 55, resetAfter: 3 * 24 * 60 * 60 + 4 * 60 * 60)
                )
            ),
            (
                UsageProvider.codex,
                snapshot(
                    now: now,
                    primary: reading(now: now, label: "5h", actual: 52, target: 50, resetAfter: 2 * 60 * 60 + 30 * 60),
                    weekly: reading(now: now, label: "week", actual: 51, target: 50, resetAfter: 3 * 24 * 60 * 60 + 12 * 60 * 60)
                )
            ),
            (
                UsageProvider.claudeCode,
                snapshot(
                    now: now,
                    primary: reading(now: now, label: "5h", actual: 68, target: 50, resetAfter: 2 * 60 * 60 + 30 * 60),
                    weekly: reading(now: now, label: "week", actual: 52, target: 50, resetAfter: 3 * 24 * 60 * 60 + 12 * 60 * 60)
                )
            ),
            (
                UsageProvider.codex,
                snapshot(
                    now: now,
                    primary: reading(now: now, label: "5h", actual: 0, target: 50, resetAfter: 2 * 60 * 60 + 30 * 60),
                    weekly: reading(now: now, label: "week", actual: 99, target: 57, resetAfter: 3 * 24 * 60 * 60)
                )
            )
        ]

        return [
            dashboard([snapshots[0]]),
            dashboard([snapshots[1]]),
            dashboard([snapshots[2], snapshots[3]]),
            dashboard([snapshots[4], snapshots[1]])
        ]
    }

    private static func dashboard(_ snapshots: [(UsageProvider, UsageSnapshot)]) -> UsageDashboardSnapshot {
        UsageDashboardSnapshot(
            providers: snapshots.map { ProviderUsageSnapshot(provider: $0.0, snapshot: $0.1) },
            fallback: snapshots.first?.1 ?? .placeholder
        )
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
