import Foundation

public enum ClaudeUsageCacheStoreError: Error, LocalizedError, Equatable {
    case cacheMissing(String)
    case unreadableCache
    case missingWindow(String)

    public var errorDescription: String? {
        switch self {
        case .cacheMissing(let path):
            return "Claude Code usage cache not found at \(path)"
        case .unreadableCache:
            return "Claude Code usage cache could not be read"
        case .missingWindow(let label):
            return "Claude Code usage cache is missing \(label) window data"
        }
    }
}

public final class ClaudeUsageCacheStore {
    private let cacheFileURL: URL
    private let decoder: JSONDecoder

    public init(
        cacheFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/cache/usage-api.json")
    ) {
        self.cacheFileURL = cacheFileURL
        self.decoder = JSONDecoder()
    }

    public func snapshot(
        state: UsageSnapshotState = .stale,
        message: String? = "Using cached Claude Code usage"
    ) throws -> UsageSnapshot {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            throw ClaudeUsageCacheStoreError.cacheMissing(cacheFileURL.path)
        }

        guard let data = try? Data(contentsOf: cacheFileURL) else {
            throw ClaudeUsageCacheStoreError.unreadableCache
        }

        let cache = try decoder.decode(ClaudeUsageCache.self, from: data)

        guard let primaryResetAt = cache.fiveHourReset?.date else {
            throw ClaudeUsageCacheStoreError.missingWindow("5h")
        }

        guard let weeklyResetAt = cache.weeklyReset?.date else {
            throw ClaudeUsageCacheStoreError.missingWindow("week")
        }

        let cachedAt = Date(timeIntervalSince1970: cache.timestamp)

        return UsageSnapshot(
            primary: UsageWindow(
                label: "5h",
                usedPercent: cache.fiveHour,
                resetAt: primaryResetAt,
                limitWindowSeconds: 5 * 60 * 60
            ).pace(at: cachedAt),
            weekly: UsageWindow(
                label: "week",
                usedPercent: cache.weekly,
                resetAt: weeklyResetAt,
                limitWindowSeconds: 7 * 24 * 60 * 60
            ).pace(at: cachedAt),
            lastRefreshedAt: cachedAt,
            state: state,
            message: message
        )
    }

    public func freshSnapshot(maxAge: TimeInterval, now: Date = Date()) throws -> UsageSnapshot? {
        let snapshot = try snapshot(state: .fresh, message: nil)
        guard now.timeIntervalSince(snapshot.lastRefreshedAt) <= maxAge else {
            return nil
        }

        return snapshot
    }
}

private struct ClaudeUsageCache: Decodable {
    let timestamp: TimeInterval
    let fiveHour: Double
    let weekly: Double
    let fiveHourReset: FlexibleDate?
    let weeklyReset: FlexibleDate?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case fiveHour = "five_hour"
        case weekly
        case fiveHourReset = "five_hour_reset"
        case weeklyReset = "weekly_reset"
    }
}
