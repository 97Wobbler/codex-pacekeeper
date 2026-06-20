import Foundation
import XCTest
@testable import CodexPacekeeperCore

final class ClaudeDirectUsageClientTests: XCTestCase {
    override func tearDown() {
        ClaudeDirectUsageMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testFetchSnapshotDecodesUsageWindows() async throws {
        ClaudeDirectUsageMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data("""
            {
              "five_hour": {
                "used_percentage": 12,
                "resets_at": 20000
              },
              "seven_day": {
                "utilization": 34,
                "resets_at": 700000
              }
            }
            """.utf8)
            return (response, data)
        }
        let client = ClaudeDirectUsageClient(
            endpoint: URL(string: "https://example.test/usage")!,
            session: mockSession()
        )

        let snapshot = try await client.fetchSnapshot(
            accessToken: "test-token",
            now: Date(timeIntervalSince1970: 10_000)
        )

        XCTAssertEqual(snapshot.state, .fresh)
        XCTAssertEqual(snapshot.primary.actualPercent, 12, accuracy: 0.0001)
        XCTAssertEqual(snapshot.weekly.actualPercent, 34, accuracy: 0.0001)
        XCTAssertEqual(snapshot.primary.resetAt, Date(timeIntervalSince1970: 20_000))
        XCTAssertEqual(snapshot.weekly.resetAt, Date(timeIntervalSince1970: 700_000))
    }

    func testFetchSnapshotAllowsInactiveZeroFiveHourWindowWithoutReset() async throws {
        ClaudeDirectUsageMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data("""
            {
              "five_hour": {
                "utilization": 0,
                "resets_at": null
              },
              "seven_day": {
                "utilization": 8,
                "resets_at": "2026-06-22T10:59:59.512527+00:00"
              }
            }
            """.utf8)
            return (response, data)
        }
        let client = ClaudeDirectUsageClient(
            endpoint: URL(string: "https://example.test/usage")!,
            session: mockSession()
        )
        let now = Date(timeIntervalSince1970: 10_000)

        let snapshot = try await client.fetchSnapshot(accessToken: "test-token", now: now)

        XCTAssertEqual(snapshot.state, .fresh)
        XCTAssertEqual(snapshot.primary.actualPercent, 0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.primary.resetAt, now.addingTimeInterval(5 * 60 * 60))
        XCTAssertEqual(snapshot.weekly.actualPercent, 8, accuracy: 0.0001)
    }

    func testFetchSnapshotThrowsUnauthorizedFor401() async throws {
        ClaudeDirectUsageMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let client = ClaudeDirectUsageClient(
            endpoint: URL(string: "https://example.test/usage")!,
            session: mockSession()
        )

        do {
            _ = try await client.fetchSnapshot(accessToken: "expired-token")
            XCTFail("Expected 401 error")
        } catch {
            XCTAssertEqual(error as? ClaudeDirectUsageClientError, .httpStatus(401))
        }
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClaudeDirectUsageMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class ClaudeDirectUsageMockURLProtocol: URLProtocol {
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
