import Foundation

public enum ClaudeAuthTokenStoreError: Error, LocalizedError, Equatable {
    case credentialsMissing(String)
    case unreadableCredentials
    case accessTokenMissing

    public var errorDescription: String? {
        switch self {
        case .credentialsMissing(let path):
            return "Claude Code credentials not found at \(path)"
        case .unreadableCredentials:
            return "Claude Code credentials could not be read"
        case .accessTokenMissing:
            return "Claude Code access token not found in credentials"
        }
    }
}

public final class ClaudeAuthTokenStore {
    private let credentialsFileURL: URL

    public init(
        credentialsFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    ) {
        self.credentialsFileURL = credentialsFileURL
    }

    public func accessToken() throws -> String {
        guard FileManager.default.fileExists(atPath: credentialsFileURL.path) else {
            throw ClaudeAuthTokenStoreError.credentialsMissing(credentialsFileURL.path)
        }

        guard let data = try? Data(contentsOf: credentialsFileURL) else {
            throw ClaudeAuthTokenStoreError.unreadableCredentials
        }

        guard let token = Self.accessToken(from: data) else {
            throw ClaudeAuthTokenStoreError.accessTokenMissing
        }

        return token
    }

    private static func accessToken(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let token = root["accessToken"] as? String, !token.isEmpty {
            return token
        }

        if
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        {
            return token
        }

        return nil
    }
}
