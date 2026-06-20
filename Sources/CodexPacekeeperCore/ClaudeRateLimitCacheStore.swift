import Foundation

public enum ClaudeRateLimitCacheStoreError: Error, LocalizedError, Equatable {
    case cacheMissing(String)
    case unreadableCache
    case missingWindow(String)

    public var errorDescription: String? {
        switch self {
        case .cacheMissing(let path):
            return "Claude Code rate limit cache not found at \(path)"
        case .unreadableCache:
            return "Claude Code rate limit cache could not be read"
        case .missingWindow(let label):
            return "Claude Code rate limit cache is missing \(label) window data"
        }
    }
}

public final class ClaudeRateLimitCacheStore {
    public static let defaultFreshnessInterval: TimeInterval = 10 * 60
    public static let resetTolerance: TimeInterval = 60

    private let cacheFileURL: URL
    private let freshnessInterval: TimeInterval
    private let decoder: JSONDecoder

    public init(
        cacheFileURL: URL = ClaudeRateLimitCacheStore.defaultFileURL(),
        freshnessInterval: TimeInterval = ClaudeRateLimitCacheStore.defaultFreshnessInterval
    ) {
        self.cacheFileURL = cacheFileURL
        self.freshnessInterval = freshnessInterval
        self.decoder = JSONDecoder()
    }

    public static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("Codex Pacekeeper", isDirectory: true)
            .appendingPathComponent("claude-rate-limits.json", isDirectory: false)
    }

    public func snapshot(now: Date = Date()) throws -> UsageSnapshot {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            throw ClaudeRateLimitCacheStoreError.cacheMissing(cacheFileURL.path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: cacheFileURL)
        } catch {
            throw ClaudeRateLimitCacheStoreError.unreadableCache
        }

        let cache: ClaudeRateLimitCache
        do {
            cache = try decoder.decode(ClaudeRateLimitCache.self, from: data)
        } catch {
            throw ClaudeRateLimitCacheStoreError.unreadableCache
        }

        guard let fiveHour = cache.fiveHour else {
            throw ClaudeRateLimitCacheStoreError.missingWindow("5h")
        }

        guard let sevenDay = cache.sevenDay else {
            throw ClaudeRateLimitCacheStoreError.missingWindow("week")
        }

        let primaryWindow = fiveHour.usageWindow(label: "5h", limitWindowSeconds: 5 * 60 * 60)
        let weeklyWindow = sevenDay.usageWindow(label: "week", limitWindowSeconds: 7 * 24 * 60 * 60)
        let observedAt = cache.timestamp.date
        let age = max(0, now.timeIntervalSince(observedAt))
        let isPastReset = now.timeIntervalSince(primaryWindow.resetAt) > Self.resetTolerance
            || now.timeIntervalSince(weeklyWindow.resetAt) > Self.resetTolerance
        let isStale = age > freshnessInterval || isPastReset
        let message: String?

        if isPastReset {
            message = "Waiting for fresh Claude Code rate limits"
        } else if isStale {
            message = "Claude Code rate limits last updated \(Self.formattedAge(age)) ago"
        } else {
            message = nil
        }

        return UsageSnapshot(
            primary: primaryWindow.pace(at: now),
            weekly: weeklyWindow.pace(at: now),
            lastRefreshedAt: observedAt,
            state: isStale ? .stale : .fresh,
            message: message
        )
    }

    private static func formattedAge(_ age: TimeInterval) -> String {
        let totalMinutes = max(1, Int((age / 60).rounded()))

        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours < 24 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h\(minutes)m"
        }

        let days = hours / 24
        let remainingHours = hours % 24

        return remainingHours == 0 ? "\(days)d" : "\(days)d\(remainingHours)h"
    }
}

private struct ClaudeRateLimitCache: Decodable {
    let timestamp: FlexibleDate
    let fiveHour: ClaudeRateLimitWindow?
    let sevenDay: ClaudeRateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct ClaudeRateLimitWindow: Decodable {
    let usedPercentage: Double
    let resetsAt: FlexibleDate

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    func usageWindow(label: String, limitWindowSeconds: TimeInterval) -> UsageWindow {
        UsageWindow(
            label: label,
            usedPercent: usedPercentage,
            resetAt: resetsAt.date,
            limitWindowSeconds: limitWindowSeconds
        )
    }
}
