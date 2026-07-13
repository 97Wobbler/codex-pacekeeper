import Foundation
import XCTest
@testable import CodexPacekeeperCore

final class WhamUsageClientTests: XCTestCase {
    override func tearDown() {
        WhamUsageMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testFetchSnapshotDecodesLegacyFiveHourAndWeeklyWindows() async throws {
        WhamUsageMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer legacy-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

            return Self.response(
                for: request,
                body: """
                {
                  "rate_limit": {
                    "primary_window": {
                      "used_percent": 12.5,
                      "limit_window_seconds": 18000,
                      "reset_at": 28000
                    },
                    "secondary_window": {
                      "used_percent": 34.5,
                      "limit_window_seconds": 604800,
                      "reset_after_seconds": 500000
                    }
                  }
                }
                """
            )
        }
        let now = Date(timeIntervalSince1970: 10_000)
        let client = makeClient()

        let snapshot = try await client.fetchSnapshot(accessToken: "legacy-token", now: now)

        XCTAssertEqual(snapshot.state, .fresh)
        XCTAssertEqual(snapshot.readings.count, 2)
        XCTAssertEqual(snapshot.readings.map(\.label), ["5h", "week"])
        XCTAssertEqual(snapshot.readings.map(\.limitWindowSeconds), [18_000, 604_800])
        XCTAssertEqual(snapshot.readings.map(\.actualPercent), [12.5, 34.5])
        XCTAssertEqual(snapshot.readings[0].resetAt, Date(timeIntervalSince1970: 28_000))
        XCTAssertEqual(snapshot.readings[1].resetAt, now.addingTimeInterval(500_000))
        XCTAssertEqual(snapshot.primary, snapshot.readings[0])
        XCTAssertEqual(snapshot.weekly, snapshot.readings[1])
    }

    func testFetchSnapshotDecodesWeeklyOnlyPrimaryWindow() async throws {
        WhamUsageMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer weekly-token")

            return Self.response(
                for: request,
                body: """
                {
                  "rate_limit": {
                    "primary_window": {
                      "used_percent": 47,
                      "limit_window_seconds": 604800,
                      "reset_at": "2026-07-20T00:00:00Z"
                    },
                    "secondary_window": null
                  }
                }
                """
            )
        }
        let now = Date(timeIntervalSince1970: 10_000)
        let client = makeClient()

        let snapshot = try await client.fetchSnapshot(accessToken: "weekly-token", now: now)

        XCTAssertEqual(snapshot.state, .fresh)
        XCTAssertEqual(snapshot.readings.count, 1)
        XCTAssertEqual(snapshot.readings[0].label, "week")
        XCTAssertEqual(snapshot.readings[0].limitWindowSeconds, 604_800)
        XCTAssertEqual(snapshot.readings[0].actualPercent, 47, accuracy: 0.0001)
        XCTAssertEqual(snapshot.primary, snapshot.readings[0])
        XCTAssertEqual(snapshot.weekly, snapshot.readings[0])
        XCTAssertEqual(snapshot.primary, snapshot.weekly)
    }

    func testFetchSnapshotRejectsResponseWithoutUsageWindows() async throws {
        WhamUsageMockURLProtocol.requestHandler = { request in
            Self.response(
                for: request,
                body: """
                {
                  "rate_limit": {
                    "primary_window": {
                      "used_percent": 12,
                      "limit_window_seconds": 0,
                      "reset_at": 28000
                    },
                    "secondary_window": {
                      "used_percent": 34,
                      "limit_window_seconds": 5.5340232221128655e20,
                      "reset_at": 700000
                    }
                  }
                }
                """
            )
        }
        let client = makeClient()

        do {
            _ = try await client.fetchSnapshot(accessToken: "test-token")
            XCTFail("Expected a missing-window error")
        } catch {
            XCTAssertEqual(error as? WhamUsageClientError, .missingWindow("usage"))
        }
    }

    func testFetchSnapshotKeepsValidWindowWhenOtherWindowIsIncomplete() async throws {
        WhamUsageMockURLProtocol.requestHandler = { request in
            Self.response(
                for: request,
                body: """
                {
                  "rate_limit": {
                    "primary_window": {
                      "used_percent": 12,
                      "reset_at": 28000
                    },
                    "secondary_window": {
                      "used_percent": 34,
                      "limit_window_seconds": 604800,
                      "reset_after_seconds": 500000
                    }
                  }
                }
                """
            )
        }
        let client = makeClient()

        let snapshot = try await client.fetchSnapshot(
            accessToken: "test-token",
            now: Date(timeIntervalSince1970: 10_000)
        )

        XCTAssertEqual(snapshot.readings.count, 1)
        XCTAssertEqual(snapshot.primary.label, "week")
        XCTAssertEqual(snapshot.weekly, snapshot.primary)
    }

    private func makeClient() -> WhamUsageClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WhamUsageMockURLProtocol.self]

        return WhamUsageClient(
            endpoint: URL(string: "https://example.test/wham/usage")!,
            session: URLSession(configuration: configuration)
        )
    }

    private static func response(for request: URLRequest, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        return (response, Data(body.utf8))
    }
}

private final class WhamUsageMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
