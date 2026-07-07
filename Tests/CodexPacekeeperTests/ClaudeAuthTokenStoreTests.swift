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

    func testPacekeeperStoreSavesOnlyClaudeOauthCredentialFields() throws {
        let credentialsURL = try writeCredentials("{}")
        defer { try? FileManager.default.removeItem(at: credentialsURL.deletingLastPathComponent()) }
        let sourceStore = ClaudeAuthTokenStore(
            credentialsFileURL: credentialsURL,
            keychainCredentialData: {
                Data("""
                {
                  "claudeAiOauth": {
                    "accessToken": "source-token",
                    "refreshToken": "source-refresh",
                    "expiresAt": 5000000,
                    "scopes": ["user:profile", "user:sessions:claude_code"],
                    "subscriptionType": "max",
                    "rateLimitTier": "default_claude_max_5x"
                  },
                  "pluginSecrets": {
                    "slack": {
                      "token": "do-not-copy"
                    }
                  }
                }
                """.utf8)
            }
        )
        let sourceCredential = try sourceStore.oauthCredential()
        var storedData: Data?
        let pacekeeperStore = PacekeeperClaudeCredentialStore(
            keychainCredentialData: { _, _ in storedData },
            writeKeychainCredentialData: { data, _ in storedData = data },
            deleteKeychainCredentialData: { _ in storedData = nil }
        )

        let storedCredential = try pacekeeperStore.saveCredential(sourceCredential)

        XCTAssertEqual(storedCredential.accessToken, "source-token")
        XCTAssertEqual(storedCredential.refreshToken, "source-refresh")
        let storedRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(storedData)) as? [String: Any])
        XCTAssertNil(storedRoot["pluginSecrets"])
        let oauth = try XCTUnwrap(storedRoot["claudeAiOauth"] as? [String: Any])
        XCTAssertEqual(oauth["accessToken"] as? String, "source-token")
        XCTAssertEqual(oauth["refreshToken"] as? String, "source-refresh")
        XCTAssertEqual(oauth["subscriptionType"] as? String, "max")
        XCTAssertEqual(oauth["rateLimitTier"] as? String, "default_claude_max_5x")
    }

    func testPacekeeperStoreReadsWithPromptPolicy() throws {
        var observedPromptPolicy: ClaudeKeychainPromptPolicy?
        let store = PacekeeperClaudeCredentialStore(
            serviceName: "test-service",
            keychainCredentialData: { serviceName, promptPolicy in
                XCTAssertEqual(serviceName, "test-service")
                observedPromptPolicy = promptPolicy
                return Data("""
                {
                  "claudeAiOauth": {
                    "accessToken": "stored-token"
                  }
                }
                """.utf8)
            },
            writeKeychainCredentialData: { _, _ in },
            deleteKeychainCredentialData: { _ in }
        )

        let credential = try store.oauthCredential(promptPolicy: .disallow)

        XCTAssertEqual(credential.accessToken, "stored-token")
        XCTAssertEqual(observedPromptPolicy, .disallow)
    }

    func testPacekeeperStoreUpdatesAndDeletesImportedCredential() throws {
        let credentialsURL = try writeCredentials("{}")
        defer { try? FileManager.default.removeItem(at: credentialsURL.deletingLastPathComponent()) }
        let sourceStore = ClaudeAuthTokenStore(
            credentialsFileURL: credentialsURL,
            keychainCredentialData: {
                Data("""
                {
                  "claudeAiOauth": {
                    "accessToken": "old-token",
                    "refreshToken": "old-refresh",
                    "expiresAt": 2000000,
                    "scopes": ["user:profile"],
                    "subscriptionType": "max"
                  }
                }
                """.utf8)
            }
        )
        let sourceCredential = try sourceStore.oauthCredential()
        var storedData: Data?
        var deletedServiceName: String?
        let pacekeeperStore = PacekeeperClaudeCredentialStore(
            serviceName: "test-service",
            keychainCredentialData: { _, _ in storedData },
            writeKeychainCredentialData: { data, serviceName in
                XCTAssertEqual(serviceName, "test-service")
                storedData = data
            },
            deleteKeychainCredentialData: { serviceName in
                deletedServiceName = serviceName
                storedData = nil
            }
        )

        let importedCredential = try pacekeeperStore.saveCredential(sourceCredential)
        let updatedCredential = try pacekeeperStore.saveRefreshResult(
            ClaudeOAuthRefreshResult(
                accessToken: "new-token",
                refreshToken: nil,
                expiresAt: Date(timeIntervalSince1970: 9_000),
                scopes: ["user:profile", "user:inference"]
            ),
            for: importedCredential
        )
        let readCredential = try pacekeeperStore.oauthCredential(promptPolicy: .disallow)

        XCTAssertEqual(updatedCredential.accessToken, "new-token")
        XCTAssertEqual(updatedCredential.refreshToken, "old-refresh")
        XCTAssertEqual(readCredential.accessToken, "new-token")
        XCTAssertEqual(readCredential.expiresAt, Date(timeIntervalSince1970: 9_000))
        XCTAssertEqual(readCredential.scopes, ["user:profile", "user:inference"])
        XCTAssertEqual(readCredential.subscriptionType, "max")

        try pacekeeperStore.deleteCredential()

        XCTAssertEqual(deletedServiceName, "test-service")
        XCTAssertThrowsError(try pacekeeperStore.oauthCredential()) { error in
            XCTAssertEqual(error as? ClaudeAuthTokenStoreError, .credentialsMissing)
        }
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
