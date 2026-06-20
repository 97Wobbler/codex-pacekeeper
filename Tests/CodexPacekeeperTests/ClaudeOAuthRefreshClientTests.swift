import Foundation
import XCTest
@testable import CodexPacekeeperCore

final class ClaudeOAuthRefreshClientTests: XCTestCase {
    override func tearDown() {
        ClaudeOAuthRefreshMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testRefreshTokenPostsClaudeOAuthPayload() async throws {
        ClaudeOAuthRefreshMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(requestBody(from: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["grant_type"] as? String, "refresh_token")
            XCTAssertEqual(json["refresh_token"] as? String, "refresh-token")
            XCTAssertEqual(json["client_id"] as? String, "test-client-id")
            XCTAssertEqual(json["scope"] as? String, "user:profile user:inference")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data("""
            {
              "access_token": "new-token",
              "refresh_token": "new-refresh",
              "expires_in": 3600,
              "scope": "user:profile user:inference"
            }
            """.utf8)
            return (response, data)
        }
        let client = ClaudeOAuthRefreshClient(
            endpoint: URL(string: "https://example.test/oauth/token")!,
            clientID: "test-client-id",
            scopes: ["user:profile", "user:inference"],
            session: mockSession()
        )
        let now = Date(timeIntervalSince1970: 1_000)

        let result = try await client.refreshToken("refresh-token", now: now)

        XCTAssertEqual(result.accessToken, "new-token")
        XCTAssertEqual(result.refreshToken, "new-refresh")
        XCTAssertEqual(result.expiresAt, Date(timeIntervalSince1970: 4_600))
        XCTAssertEqual(result.scopes, ["user:profile", "user:inference"])
    }

    func testRefreshTokenThrowsRateLimitErrorFor429() async throws {
        ClaudeOAuthRefreshMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let client = ClaudeOAuthRefreshClient(
            endpoint: URL(string: "https://example.test/oauth/token")!,
            session: mockSession()
        )

        do {
            _ = try await client.refreshToken("refresh-token")
            XCTFail("Expected 429 error")
        } catch {
            XCTAssertEqual(error as? ClaudeOAuthRefreshClientError, .httpStatus(429))
        }
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClaudeOAuthRefreshMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private func requestBody(from request: URLRequest) -> Data? {
    if let httpBody = request.httpBody {
        return httpBody
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)

    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)

        guard count > 0 else {
            break
        }

        data.append(buffer, count: count)
    }

    return data
}

private final class ClaudeOAuthRefreshMockURLProtocol: URLProtocol {
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
