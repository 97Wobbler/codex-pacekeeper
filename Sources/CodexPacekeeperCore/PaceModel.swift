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
            limitWindowSeconds: limitWindowSeconds,
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
    public let limitWindowSeconds: TimeInterval
    public let status: PaceStatus
    public let isPaused: Bool

    public init(
        label: String,
        actualPercent: Double,
        recommendedPercent: Double,
        deltaPercentagePoints: Double,
        resetAt: Date,
        limitWindowSeconds: TimeInterval = 5 * 60 * 60,
        status: PaceStatus,
        isPaused: Bool
    ) {
        self.label = label
        self.actualPercent = actualPercent
        self.recommendedPercent = recommendedPercent
        self.deltaPercentagePoints = deltaPercentagePoints
        self.resetAt = resetAt
        self.limitWindowSeconds = limitWindowSeconds
        self.status = status
        self.isPaused = isPaused
    }

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

        if status == .steady {
            return "Hold this pace"
        }

        if deltaPercentagePoints < 0 {
            switch status {
            case .easy, .tempo:
                return "Pick up pace"
            case .threshold:
                return "Push harder"
            case .redline:
                return "Use more now"
            case .steady:
                return "Hold this pace"
            }
        }

        switch status {
        case .easy:
            return "Pick up pace"
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
            limitWindowSeconds: limitWindowSeconds,
            status: status,
            isPaused: paused
        )
    }
}

public struct PaceRecommendation: Equatable {
    public let action: String
    public let guidance: String
    public let status: PaceStatus

    public init(primary: PaceReading, weekly: PaceReading, trend: UsageTrend? = nil) {
        if primary.isPaused || weekly.isPaused {
            self.init(action: "Paused", status: .steady)
            return
        }

        if weekly.actualPercent >= 90 || weekly.deltaPercentagePoints > 35 {
            self.init(action: "Short efforts only", status: .redline)
            return
        }

        if weekly.deltaPercentagePoints > 20 {
            self.init(action: "Taper recommended", status: .threshold)
            return
        }

        if weekly.deltaPercentagePoints > 10 {
            self.init(primary: primary, weekly: weekly, action: "Ease up soon", status: .tempo, trend: trend)
            return
        }

        if weekly.deltaPercentagePoints < -10 && primary.deltaPercentagePoints < 35 {
            let behindReading = abs(weekly.deltaPercentagePoints) > abs(primary.deltaPercentagePoints) ? weekly : primary
            self.init(primary: primary, weekly: weekly, action: behindReading.guidance, status: behindReading.status, trend: trend)
            return
        }

        self.init(primary: primary, weekly: weekly, action: primary.guidance, status: primary.status, trend: trend)
    }

    private init(action: String, status: PaceStatus) {
        self.action = action
        self.guidance = action
        self.status = status
    }

    private init(primary: PaceReading, weekly: PaceReading, action: String, status: PaceStatus, trend: UsageTrend?) {
        guard let trend else {
            self.init(action: action, status: status)
            return
        }

        let expectedPrimaryRate = 100 / (primary.limitWindowHours)
        let expectedWeeklyRate = 100 / (weekly.limitWindowHours)
        let primaryRate = max(0, trend.primaryPercentPointsPerHour)
        let weeklyRate = max(0, trend.weeklyPercentPointsPerHour)
        let sharplyIncreasingBurn = primaryRate >= expectedPrimaryRate * 2
            || (weekly.deltaPercentagePoints >= -5 && weeklyRate >= expectedWeeklyRate * 8)

        if sharplyIncreasingBurn {
            switch status {
            case .easy:
                self.init(action: "Hold this pace", status: .steady)
            case .steady:
                self.init(action: "Ease up soon", status: .tempo)
            case .tempo:
                self.init(action: "Taper recommended", status: .threshold)
            case .threshold, .redline:
                self.init(action: action, status: status)
            }
            return
        }

        if primary.deltaPercentagePoints <= -5 && primaryRate <= expectedPrimaryRate * 0.1 {
            self.init(action: "Pick up pace", status: .easy)
            return
        }

        self.init(action: action, status: status)
    }
}

public enum UsageSnapshotState: String, Equatable {
    case loading
    case fresh
    case stale
    case error
}

public enum PaceStatus: String, Equatable {
    case easy
    case steady
    case tempo
    case threshold
    case redline

    public static func status(forActualPercent actualPercent: Double, deltaPercentagePoints delta: Double) -> PaceStatus {
        let distance = abs(delta)

        if distance > 35 || actualPercent >= 90 {
            return .redline
        }

        if distance > 20 {
            return .threshold
        }

        if distance > 10 {
            return .tempo
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
    public let state: UsageSnapshotState
    public let message: String?
    public let trend: UsageTrend?

    public init(
        primary: PaceReading,
        weekly: PaceReading,
        lastRefreshedAt: Date,
        state: UsageSnapshotState,
        message: String?,
        trend: UsageTrend? = nil
    ) {
        self.primary = primary
        self.weekly = weekly
        self.lastRefreshedAt = lastRefreshedAt
        self.state = state
        self.message = message
        self.trend = trend
    }

    public var isStale: Bool {
        state == .stale
    }

    public var hasUsageData: Bool {
        state == .fresh || state == .stale
    }

    public var paceRecommendation: PaceRecommendation {
        PaceRecommendation(primary: primary, weekly: weekly, trend: trend)
    }

    public var menuBarTitle: String {
        switch state {
        case .loading:
            return "PK ..."
        case .error:
            return "PK ?"
        case .fresh, .stale:
            return primary.menuBarTitle
        }
    }

    public var stateLabel: String {
        switch state {
        case .loading:
            return "loading"
        case .fresh:
            return "fresh"
        case .stale:
            return "stale"
        case .error:
            return "error"
        }
    }

    public var stateSystemImageName: String {
        switch state {
        case .loading:
            return "hourglass"
        case .error:
            return "questionmark.circle"
        case .fresh, .stale:
            return primary.status.systemImageName
        }
    }

    public static var placeholder: UsageSnapshot {
        let now = Date()
        let fiveHours: TimeInterval = 5 * 60 * 60
        let week: TimeInterval = 7 * 24 * 60 * 60

        return UsageSnapshot(
            primary: UsageWindow(
                label: "5h",
                usedPercent: 0,
                resetAt: now.addingTimeInterval(fiveHours),
                limitWindowSeconds: fiveHours
            ).pace(at: now),
            weekly: UsageWindow(
                label: "week",
                usedPercent: 0,
                resetAt: now.addingTimeInterval(week),
                limitWindowSeconds: week
            ).pace(at: now),
            lastRefreshedAt: now,
            state: .loading,
            message: "Fetching usage",
            trend: nil
        )
    }

    public static func unavailable(now: Date = Date(), message: String) -> UsageSnapshot {
        let fiveHours: TimeInterval = 5 * 60 * 60
        let week: TimeInterval = 7 * 24 * 60 * 60

        return UsageSnapshot(
            primary: UsageWindow(
                label: "5h",
                usedPercent: 0,
                resetAt: now.addingTimeInterval(fiveHours),
                limitWindowSeconds: fiveHours
            ).pace(at: now),
            weekly: UsageWindow(
                label: "week",
                usedPercent: 0,
                resetAt: now.addingTimeInterval(week),
                limitWindowSeconds: week
            ).pace(at: now),
            lastRefreshedAt: now,
            state: .error,
            message: message,
            trend: nil
        )
    }

    public func withPaused(_ paused: Bool) -> UsageSnapshot {
        UsageSnapshot(
            primary: primary.withPaused(paused),
            weekly: weekly.withPaused(paused),
            lastRefreshedAt: lastRefreshedAt,
            state: state,
            message: message,
            trend: trend
        )
    }

    public func markingStale(message: String) -> UsageSnapshot {
        UsageSnapshot(
            primary: primary,
            weekly: weekly,
            lastRefreshedAt: lastRefreshedAt,
            state: .stale,
            message: message,
            trend: trend
        )
    }

    public func withTrend(_ trend: UsageTrend?) -> UsageSnapshot {
        UsageSnapshot(
            primary: primary,
            weekly: weekly,
            lastRefreshedAt: lastRefreshedAt,
            state: state,
            message: message,
            trend: trend
        )
    }
}

private extension PaceReading {
    var limitWindowHours: Double {
        max(limitWindowSeconds / 3_600, 1 / 60)
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
