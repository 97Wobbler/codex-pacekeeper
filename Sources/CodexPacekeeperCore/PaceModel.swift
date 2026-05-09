import Foundation

public struct UsageWindow: Equatable {
    public let label: String
    public let usedPercent: Double
    public let resetAt: Date
    public let limitWindowSeconds: TimeInterval

    public init(label: String, usedPercent: Double, resetAt: Date, limitWindowSeconds: TimeInterval) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.limitWindowSeconds = limitWindowSeconds
    }

    public func pace(at now: Date) -> PaceReading {
        let windowStart = resetAt.addingTimeInterval(-limitWindowSeconds)
        let elapsed = now.timeIntervalSince(windowStart)
        let recommended = (elapsed / limitWindowSeconds * 100).clamped(to: 0...100)
        let actual = usedPercent.clamped(to: 0...100)
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

public struct PaceReading: Equatable {
    public let label: String
    public let actualPercent: Double
    public let recommendedPercent: Double
    public let deltaPercentagePoints: Double
    public let resetAt: Date
    public let status: PaceStatus
    public let isPaused: Bool

    public var menuBarTitle: String {
        if isPaused {
            return "PK paused"
        }

        return "PK \(deltaPercentagePoints.signedRounded)"
    }

    public var guidance: String {
        if isPaused {
            return "Paused"
        }

        switch status {
        case .easy:
            return "Room to move"
        case .steady:
            return "Hold this pace"
        case .tempo:
            return "Ease up soon"
        case .threshold:
            return "Taper recommended"
        case .redline:
            return "Short efforts only"
        }
    }

    public func withPaused(_ paused: Bool) -> PaceReading {
        PaceReading(
            label: label,
            actualPercent: actualPercent,
            recommendedPercent: recommendedPercent,
            deltaPercentagePoints: deltaPercentagePoints,
            resetAt: resetAt,
            status: status,
            isPaused: paused
        )
    }
}

public enum PaceStatus: String, Equatable {
    case easy
    case steady
    case tempo
    case threshold
    case redline

    public static func status(forActualPercent actualPercent: Double, deltaPercentagePoints delta: Double) -> PaceStatus {
        if delta > 35 || actualPercent >= 90 {
            return .redline
        }

        if delta > 20 {
            return .threshold
        }

        if delta > 10 {
            return .tempo
        }

        if delta <= -10 {
            return .easy
        }

        return .steady
    }

    public var systemImageName: String {
        switch self {
        case .easy:
            return "figure.run"
        case .steady:
            return "flag.checkered"
        case .tempo:
            return "speedometer"
        case .threshold:
            return "exclamationmark.triangle"
        case .redline:
            return "flame"
        }
    }
}

public struct UsageSnapshot: Equatable {
    public let primary: PaceReading
    public let weekly: PaceReading
    public let lastRefreshedAt: Date
    public let isStale: Bool

    public static var placeholder: UsageSnapshot {
        let now = Date()
        let fiveHours: TimeInterval = 5 * 60 * 60
        let week: TimeInterval = 7 * 24 * 60 * 60

        return UsageSnapshot(
            primary: UsageWindow(
                label: "5h",
                usedPercent: 42,
                resetAt: now.addingTimeInterval(3 * 60 * 60),
                limitWindowSeconds: fiveHours
            ).pace(at: now),
            weekly: UsageWindow(
                label: "week",
                usedPercent: 44,
                resetAt: now.addingTimeInterval(2 * 24 * 60 * 60),
                limitWindowSeconds: week
            ).pace(at: now),
            lastRefreshedAt: now,
            isStale: false
        )
    }

    public func withPaused(_ paused: Bool) -> UsageSnapshot {
        UsageSnapshot(
            primary: primary.withPaused(paused),
            weekly: weekly.withPaused(paused),
            lastRefreshedAt: lastRefreshedAt,
            isStale: isStale
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }

    var signedRounded: String {
        let roundedValue = Int(rounded())
        return roundedValue >= 0 ? "+\(roundedValue)" : "\(roundedValue)"
    }
}
