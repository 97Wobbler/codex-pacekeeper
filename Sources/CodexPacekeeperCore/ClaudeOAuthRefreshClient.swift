import Foundation

public enum ClaudeOAuthRefreshClientError: Error, LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case accessTokenMissing
    case expiresInMissing

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Claude OAuth refresh returned an invalid response"
        case .httpStatus(429):
            return "Claude OAuth refresh is rate limited"
        case .httpStatus(401), .httpStatus(403):
            return "Claude OAuth refresh is not authorized"
        case .httpStatus(let status):
            return "Claude OAuth refresh returned HTTP \(status)"
        case .accessTokenMissing:
            return "Claude OAuth refresh response is missing an access token"
        case .expiresInMissing:
            return "Claude OAuth refresh response is missing an expiry"
        }
    }
}

public struct ClaudeOAuthRefreshResult: Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
    public let scopes: [String]
}

public final class ClaudeOAuthRefreshClient {
    private let endpoint: URL
    private let clientID: String
    private let scopes: [String]
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        endpoint: URL = URL(string: "https://platform.claude.com/v1/oauth/token")!,
        clientID: String = "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        scopes: [String] = [
            "user:profile",
            "user:inference",
            "user:sessions:claude_code",
            "user:mcp_servers"
        ],
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.clientID = clientID
        self.scopes = scopes
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func refreshToken(
        _ refreshToken: String,
        now: Date = Date()
    ) async throws -> ClaudeOAuthRefreshResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            ClaudeOAuthRefreshRequest(
                refreshToken: refreshToken,
                clientID: clientID,
                scope: scopes.joined(separator: " ")
            )
        )
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeOAuthRefreshClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClaudeOAuthRefreshClientError.httpStatus(httpResponse.statusCode)
        }

        let tokenResponse = try decoder.decode(ClaudeOAuthRefreshResponse.self, from: data)

        guard !tokenResponse.accessToken.isEmpty else {
            throw ClaudeOAuthRefreshClientError.accessTokenMissing
        }

        guard let expiresIn = tokenResponse.expiresIn else {
            throw ClaudeOAuthRefreshClientError.expiresInMissing
        }

        return ClaudeOAuthRefreshResult(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: now.addingTimeInterval(expiresIn),
            scopes: tokenResponse.scope?
                .split(separator: " ")
                .map(String.init) ?? scopes
        )
    }
}

private struct ClaudeOAuthRefreshRequest: Encodable {
    let grantType = "refresh_token"
    let refreshToken: String
    let clientID: String
    let scope: String

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case refreshToken = "refresh_token"
        case clientID = "client_id"
        case scope
    }
}

private struct ClaudeOAuthRefreshResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }
}
