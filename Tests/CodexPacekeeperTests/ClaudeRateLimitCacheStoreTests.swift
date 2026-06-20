import XCTest
@testable import CodexPacekeeperCore

final class ClaudeRateLimitCacheStoreTests: XCTestCase {
    func testFreshCacheProducesUsageSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_060)
        let cacheURL = try writeCache(
            timestamp: 1_000,
            fiveHourUsed: 12,
            fiveHourReset: 1_000 + 5 * 60 * 60,
            sevenDayUsed: 34,
            sevenDayReset: 1_000 + 7 * 24 * 60 * 60
        )
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        let store = ClaudeRateLimitCacheStore(cacheFileURL: cacheURL, freshnessInterval: 10 * 60)

        let snapshot = try store.snapshot(now: now)

        XCTAssertEqual(snapshot.state, .fresh)
        XCTAssertNil(snapshot.message)
        XCTAssertEqual(snapshot.primary.actualPercent, 12, accuracy: 0.0001)
        XCTAssertEqual(snapshot.weekly.actualPercent, 34, accuracy: 0.0001)
        XCTAssertEqual(snapshot.lastRefreshedAt, Date(timeIntervalSince1970: 1_000))
    }

    func testOldCacheIsReturnedAsStaleSnapshot() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let cacheURL = try writeCache(
            timestamp: 1_000,
            fiveHourUsed: 12,
            fiveHourReset: 1_000 + 5 * 60 * 60,
            sevenDayUsed: 34,
            sevenDayReset: 1_000 + 7 * 24 * 60 * 60
        )
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        let store = ClaudeRateLimitCacheStore(cacheFileURL: cacheURL, freshnessInterval: 60)

        let snapshot = try store.snapshot(now: now)

        XCTAssertEqual(snapshot.state, .stale)
        XCTAssertEqual(snapshot.primary.actualPercent, 12, accuracy: 0.0001)
        XCTAssertEqual(snapshot.message, "Claude Code rate limits last updated 17m ago")
    }

    func testCachePastResetIsReturnedAsStaleSnapshot() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let cacheURL = try writeCache(
            timestamp: 19_900,
            fiveHourUsed: 12,
            fiveHourReset: 19_800,
            sevenDayUsed: 34,
            sevenDayReset: 19_900 + 7 * 24 * 60 * 60
        )
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        let store = ClaudeRateLimitCacheStore(cacheFileURL: cacheURL, freshnessInterval: 10 * 60)

        let snapshot = try store.snapshot(now: now)

        XCTAssertEqual(snapshot.state, .stale)
        XCTAssertEqual(snapshot.message, "Waiting for fresh Claude Code rate limits")
    }

    func testMissingCacheThrowsCacheMissing() {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("missing.json", isDirectory: false)
        let store = ClaudeRateLimitCacheStore(cacheFileURL: cacheURL)

        XCTAssertThrowsError(try store.snapshot()) { error in
            guard
                let cacheError = error as? ClaudeRateLimitCacheStoreError,
                case .cacheMissing = cacheError
            else {
                XCTFail("Expected cacheMissing, got \(error)")
                return
            }
        }
    }

    private func writeCache(
        timestamp: TimeInterval,
        fiveHourUsed: Double,
        fiveHourReset: TimeInterval,
        sevenDayUsed: Double,
        sevenDayReset: TimeInterval
    ) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let cacheURL = directoryURL.appendingPathComponent("claude-rate-limits.json", isDirectory: false)
        let json = """
        {
          "schema_version": 1,
          "source": "claude-code-statusline",
          "timestamp": \(timestamp),
          "five_hour": {
            "used_percentage": \(fiveHourUsed),
            "resets_at": \(fiveHourReset)
          },
          "seven_day": {
            "used_percentage": \(sevenDayUsed),
            "resets_at": \(sevenDayReset)
          }
        }
        """
        try Data(json.utf8).write(to: cacheURL)
        return cacheURL
    }
}
