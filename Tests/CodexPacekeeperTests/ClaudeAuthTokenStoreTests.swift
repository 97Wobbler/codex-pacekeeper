import XCTest
@testable import CodexPacekeeperCore

final class ClaudeAuthTokenStoreTests: XCTestCase {
    func testReadsTopLevelAccessToken() throws {
        let credentialsURL = try writeCredentials("""
        {
          "accessToken": "top-level-token"
        }
        """)
        defer { try? FileManager.default.removeItem(at: credentialsURL.deletingLastPathComponent()) }
        let store = ClaudeAuthTokenStore(credentialsFileURL: credentialsURL, keychainCredentialData: { nil })

        XCTAssertEqual(try store.accessToken(), "top-level-token")
    }

    func testReadsNestedClaudeOauthAccessToken() throws {
        let credentialsURL = try writeCredentials("""
        {
          "claudeAiOauth": {
            "accessToken": "nested-token"
          }
        }
        """)
        defer { try? FileManager.default.removeItem(at: credentialsURL.deletingLastPathComponent()) }
        let store = ClaudeAuthTokenStore(credentialsFileURL: credentialsURL, keychainCredentialData: { nil })

        XCTAssertEqual(try store.accessToken(), "nested-token")
    }

    func testReadsKeychainCredentialBeforeFileCredential() throws {
        let credentialsURL = try writeCredentials("""
        {
          "claudeAiOauth": {
            "accessToken": "file-token"
          }
        }
        """)
        defer { try? FileManager.default.removeItem(at: credentialsURL.deletingLastPathComponent()) }
        let store = ClaudeAuthTokenStore(
            credentialsFileURL: credentialsURL,
            keychainCredentialData: {
                Data("""
                {
                  "claudeAiOauth": {
                    "accessToken": "keychain-token"
                  }
                }
                """.utf8)
            }
        )

        XCTAssertEqual(try store.accessToken(), "keychain-token")
    }

    func testReadsRefreshMetadataFromKeychainCredential() throws {
        let credentialsURL = try writeCredentials("{}")
        defer { try? FileManager.default.removeItem(at: credentialsURL.deletingLastPathComponent()) }
        let store = ClaudeAuthTokenStore(
            credentialsFileURL: credentialsURL,
            keychainCredentialData: {
                Data("""
                {
                  "claudeAiOauth": {
                    "accessToken": "keychain-token",
                    "refreshToken": "refresh-token",
                    "expiresAt": 2000000,
                    "scopes": ["user:profile", "user:inference"],
                    "subscriptionType": "max",
                    "rateLimitTier": "default_claude_max_5x"
                  }
                }
                """.utf8)
            }
        )

        let credential = try store.oauthCredential()

        XCTAssertEqual(credential.accessToken, "keychain-token")
        XCTAssertEqual(credential.refreshToken, "refresh-token")
        XCTAssertEqual(credential.expiresAt, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(credential.scopes, ["user:profile", "user:inference"])
        XCTAssertEqual(credential.subscriptionType, "max")
        XCTAssertEqual(credential.rateLimitTier, "default_claude_max_5x")
        XCTAssertTrue(credential.isExpired(at: Date(timeIntervalSince1970: 2_001), leeway: 0))
    }

    func testReadsHexEncodedKeychainCredential() throws {
        let credentialsURL = try writeCredentials("{}")
        defer { try? FileManager.default.removeItem(at: credentialsURL.deletingLastPathComponent()) }
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "hex-token"
          }
        }
        """
        let hex = Data(json.utf8)
            .map { String(format: "%02x", $0) }
            .joined()
        let store = ClaudeAuthTokenStore(
            credentialsFileURL: credentialsURL,
            keychainCredentialData: { Data(hex.utf8) }
        )

        XCTAssertEqual(try store.accessToken(), "hex-token")
    }

    func testSaveRefreshResultUpdatesOauthCredential() throws {
        let credentialsURL = try writeCredentials("{}")
        defer { try? FileManager.default.removeItem(at: credentialsURL.deletingLastPathComponent()) }
        let store = ClaudeAuthTokenStore(
            credentialsFileURL: credentialsURL,
            keychainCredentialData: {
                Data("""
                {
                  "claudeAiOauth": {
                    "accessToken": "old-token",
                    "refreshToken": "old-refresh",
                    "expiresAt": 2000000,
                    "scopes": ["user:profile"],
                    "subscriptionType": "max",
                    "rateLimitTier": "default_claude_max_5x"
                  }
                }
                """.utf8)
            }
        )
        let credential = try store.oauthCredential()

        let updatedCredential = try store.saveRefreshResult(
            ClaudeOAuthRefreshResult(
                accessToken: "new-token",
                refreshToken: "new-refresh",
                expiresAt: Date(timeIntervalSince1970: 5_000),
                scopes: ["user:profile", "user:inference"]
            ),
            for: credential
        )

        XCTAssertEqual(updatedCredential.accessToken, "new-token")
        XCTAssertEqual(updatedCredential.refreshToken, "new-refresh")
        XCTAssertEqual(updatedCredential.expiresAt, Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(updatedCredential.scopes, ["user:profile", "user:inference"])
        XCTAssertEqual(updatedCredential.subscriptionType, "max")
        XCTAssertEqual(updatedCredential.rateLimitTier, "default_claude_max_5x")
    }

    func testMissingAccessTokenThrows() throws {
        let credentialsURL = try writeCredentials("{}")
        defer { try? FileManager.default.removeItem(at: credentialsURL.deletingLastPathComponent()) }
        let store = ClaudeAuthTokenStore(credentialsFileURL: credentialsURL, keychainCredentialData: { nil })

        XCTAssertThrowsError(try store.accessToken()) { error in
            XCTAssertEqual(error as? ClaudeAuthTokenStoreError, .accessTokenMissing)
        }
    }

    private func writeCredentials(_ json: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let credentialsURL = directoryURL.appendingPathComponent("credentials.json", isDirectory: false)
        try Data(json.utf8).write(to: credentialsURL)
        return credentialsURL
    }
}
