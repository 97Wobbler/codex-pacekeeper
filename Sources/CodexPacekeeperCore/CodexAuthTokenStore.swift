import Foundation

public enum CodexAuthTokenStoreError: Error, LocalizedError, Equatable {
    case authFileMissing(String)
    case unreadableAuthFile
    case accessTokenMissing

    public var errorDescription: String? {
        switch self {
        case .authFileMissing(let path):
            return "Codex auth file not found at \(path)"
        case .unreadableAuthFile:
            return "Codex auth file could not be read"
        case .accessTokenMissing:
            return "Codex access token not found in auth file"
        }
    }
}

public final class CodexAuthTokenStore {
    private let authFileURL: URL

    public init(authFileURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")) {
        self.authFileURL = authFileURL
    }

    public func accessToken() throws -> String {
        guard FileManager.default.fileExists(atPath: authFileURL.path) else {
            throw CodexAuthTokenStoreError.authFileMissing(authFileURL.path)
        }

        guard
            let data = try? Data(contentsOf: authFileURL),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw CodexAuthTokenStoreError.unreadableAuthFile
        }

        if let token = root["access_token"] as? String, !token.isEmpty {
            return token
        }

        if
            let tokens = root["tokens"] as? [String: Any],
            let token = tokens["access_token"] as? String,
            !token.isEmpty
        {
            return token
        }

        throw CodexAuthTokenStoreError.accessTokenMissing
    }
}
