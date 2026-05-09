import Foundation

public struct UsageSample: Codable, Equatable {
    public let timestamp: Date
    public let primaryUsedPercent: Double
    public let primaryResetAt: Date
    public let weeklyUsedPercent: Double
    public let weeklyResetAt: Date

    public init(
        timestamp: Date,
        primaryUsedPercent: Double,
        primaryResetAt: Date,
        weeklyUsedPercent: Double,
        weeklyResetAt: Date
    ) {
        self.timestamp = timestamp
        self.primaryUsedPercent = primaryUsedPercent
        self.primaryResetAt = primaryResetAt
        self.weeklyUsedPercent = weeklyUsedPercent
        self.weeklyResetAt = weeklyResetAt
    }

    public init(snapshot: UsageSnapshot) {
        self.init(
            timestamp: snapshot.lastRefreshedAt,
            primaryUsedPercent: snapshot.primary.actualPercent,
            primaryResetAt: snapshot.primary.resetAt,
            weeklyUsedPercent: snapshot.weekly.actualPercent,
            weeklyResetAt: snapshot.weekly.resetAt
        )
    }
}

public struct UsageTrend: Equatable {
    public let primaryPercentPointsPerHour: Double
    public let weeklyPercentPointsPerHour: Double
    public let sampleCount: Int
    public let interval: TimeInterval
}

public final class UsageHistoryStore {
    public static let defaultMaxAge: TimeInterval = 7 * 24 * 60 * 60
    public static let defaultMaxSamples = 2_000

    private let fileURL: URL
    private let maxAge: TimeInterval
    private let maxSamples: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileURL: URL = UsageHistoryStore.defaultFileURL(),
        maxAge: TimeInterval = UsageHistoryStore.defaultMaxAge,
        maxSamples: Int = UsageHistoryStore.defaultMaxSamples
    ) {
        self.fileURL = fileURL
        self.maxAge = maxAge
        self.maxSamples = maxSamples

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("Codex Pacekeeper", isDirectory: true)
            .appendingPathComponent("usage-samples.json", isDirectory: false)
    }

    public func record(_ sample: UsageSample) throws {
        var samples = try loadSamples()
        samples.append(sample)
        samples = Self.pruned(samples, now: sample.timestamp, maxAge: maxAge, maxSamples: maxSamples)
        try save(samples)
    }

    public func loadSamples() throws -> [UsageSample] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([UsageSample].self, from: data)
    }

    public func recentTrend(now: Date = Date()) throws -> UsageTrend? {
        try Self.recentTrend(samples: loadSamples(), now: now)
    }

    public static func recentTrend(
        samples: [UsageSample],
        now: Date,
        preferredWindow: TimeInterval = 60 * 60,
        minimumInterval: TimeInterval = 5 * 60,
        resetTolerance: TimeInterval = 60
    ) -> UsageTrend? {
        let candidates = samples.filter { $0.timestamp <= now }
        guard let latest = candidates.max(by: { $0.timestamp < $1.timestamp }) else {
            return nil
        }

        let windowStart = now.addingTimeInterval(-preferredWindow)
        let filtered = candidates
            .filter { $0.timestamp >= windowStart && $0.timestamp <= now }
            .filter {
                abs($0.primaryResetAt.timeIntervalSince(latest.primaryResetAt)) <= resetTolerance
                    && abs($0.weeklyResetAt.timeIntervalSince(latest.weeklyResetAt)) <= resetTolerance
            }
            .sorted { $0.timestamp < $1.timestamp }

        guard let first = filtered.first, let last = filtered.last, first.timestamp < last.timestamp else {
            return nil
        }

        let interval = last.timestamp.timeIntervalSince(first.timestamp)
        guard interval >= minimumInterval else {
            return nil
        }

        let hours = interval / 3_600
        return UsageTrend(
            primaryPercentPointsPerHour: (last.primaryUsedPercent - first.primaryUsedPercent) / hours,
            weeklyPercentPointsPerHour: (last.weeklyUsedPercent - first.weeklyUsedPercent) / hours,
            sampleCount: filtered.count,
            interval: interval
        )
    }

    static func pruned(
        _ samples: [UsageSample],
        now: Date,
        maxAge: TimeInterval,
        maxSamples: Int
    ) -> [UsageSample] {
        let cutoff = now.addingTimeInterval(-maxAge)
        let recent = samples
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }

        guard recent.count > maxSamples else {
            return recent
        }

        return Array(recent.suffix(maxSamples))
    }

    private func save(_ samples: [UsageSample]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try encoder.encode(samples).write(to: fileURL, options: [.atomic])
    }
}
