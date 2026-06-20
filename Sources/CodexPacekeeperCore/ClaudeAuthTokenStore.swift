import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Security)
import Security
#endif

public enum ClaudeAuthTokenStoreError: Error, LocalizedError, Equatable {
    case credentialsMissing
    case unreadableCredentials
    case accessTokenMissing
    case refreshTokenMissing
    case credentialsNotWritable

    public var errorDescription: String? {
        switch self {
        case .credentialsMissing:
            return "Claude Code credentials not found"
        case .unreadableCredentials:
            return "Claude Code credentials could not be read"
        case .accessTokenMissing:
            return "Claude Code access token not found in credentials"
        case .refreshTokenMissing:
            return "Claude Code refresh token not found in credentials"
        case .credentialsNotWritable:
            return "Claude Code credentials could not be updated"
        }
    }
}

public struct ClaudeOAuthCredential: Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let scopes: [String]
    public let subscriptionType: String?
    public let rateLimitTier: String?

    fileprivate let record: ClaudeCredentialRecord

    public func isExpired(at now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else {
            return false
        }

        return expiresAt.timeIntervalSince(now) <= leeway
    }

    public static func == (lhs: ClaudeOAuthCredential, rhs: ClaudeOAuthCredential) -> Bool {
        lhs.accessToken == rhs.accessToken
            && lhs.refreshToken == rhs.refreshToken
            && lhs.expiresAt == rhs.expiresAt
            && lhs.scopes == rhs.scopes
            && lhs.subscriptionType == rhs.subscriptionType
            && lhs.rateLimitTier == rhs.rateLimitTier
    }
}

public final class ClaudeAuthTokenStore {
    private let credentialsFileURL: URL
    private let keychainCredentialRecord: () throws -> ClaudeCredentialRecord?

    public convenience init(
        credentialsFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json", isDirectory: false)
    ) {
        self.init(
            credentialsFileURL: credentialsFileURL,
            keychainCredentialRecord: { try Self.defaultKeychainCredentialRecord() }
        )
    }

    init(
        credentialsFileURL: URL,
        keychainCredentialData: @escaping () throws -> Data?
    ) {
        self.credentialsFileURL = credentialsFileURL
        self.keychainCredentialRecord = {
            guard let data = try keychainCredentialData() else {
                return nil
            }

            return try Self.credentialRecord(from: data, source: .injected)
        }
    }

    private init(
        credentialsFileURL: URL,
        keychainCredentialRecord: @escaping () throws -> ClaudeCredentialRecord?
    ) {
        self.credentialsFileURL = credentialsFileURL
        self.keychainCredentialRecord = keychainCredentialRecord
    }

    public func accessToken() throws -> String {
        try oauthCredential().accessToken
    }

    public func oauthCredential() throws -> ClaudeOAuthCredential {
        let record = try credentialRecord()
        guard let credential = Self.oauthCredential(from: record) else {
            throw ClaudeAuthTokenStoreError.accessTokenMissing
        }

        return credential
    }

    public func saveRefreshResult(
        _ refreshResult: ClaudeOAuthRefreshResult,
        for credential: ClaudeOAuthCredential
    ) throws -> ClaudeOAuthCredential {
        var root = credential.record.root
        var oauth = root["claudeAiOauth"] as? [String: Any] ?? [:]
        oauth["accessToken"] = refreshResult.accessToken
        oauth["refreshToken"] = refreshResult.refreshToken ?? credential.refreshToken
        oauth["expiresAt"] = Int(refreshResult.expiresAt.timeIntervalSince1970 * 1_000)
        oauth["scopes"] = refreshResult.scopes

        if let subscriptionType = credential.subscriptionType {
            oauth["subscriptionType"] = subscriptionType
        }

        if let rateLimitTier = credential.rateLimitTier {
            oauth["rateLimitTier"] = rateLimitTier
        }

        root["claudeAiOauth"] = oauth

        let updatedRecord = ClaudeCredentialRecord(root: root, source: credential.record.source)
        try writeCredentialRecord(updatedRecord)

        guard let updatedCredential = Self.oauthCredential(from: updatedRecord) else {
            throw ClaudeAuthTokenStoreError.accessTokenMissing
        }

        return updatedCredential
    }

    private func credentialRecord() throws -> ClaudeCredentialRecord {
        var foundCredentials = false
        var unreadableCredentials = false

        do {
            if let record = try keychainCredentialRecord() {
                foundCredentials = true
                return record
            }
        } catch {
            unreadableCredentials = true
        }

        if FileManager.default.fileExists(atPath: credentialsFileURL.path) {
            foundCredentials = true

            do {
                let data = try Data(contentsOf: credentialsFileURL)
                return try Self.credentialRecord(from: data, source: .file(credentialsFileURL))
            } catch {
                unreadableCredentials = true
            }
        }

        if unreadableCredentials {
            throw ClaudeAuthTokenStoreError.unreadableCredentials
        }

        guard foundCredentials else {
            throw ClaudeAuthTokenStoreError.credentialsMissing
        }

        throw ClaudeAuthTokenStoreError.accessTokenMissing
    }

    private func writeCredentialRecord(_ record: ClaudeCredentialRecord) throws {
        let data = try Self.serializedCredentials(from: record.root)

        switch record.source {
        case .keychain(let serviceName):
            try Self.writeKeychainCredentialData(data, serviceName: serviceName)
        case .file(let url):
            try data.write(to: url)
        case .injected:
            break
        }
    }

    private static func defaultKeychainCredentialRecord() throws -> ClaudeCredentialRecord? {
        for serviceName in defaultKeychainServiceNames() {
            if let data = try keychainCredentialData(serviceName: serviceName) {
                return try credentialRecord(from: data, source: .keychain(serviceName: serviceName))
            }
        }

        return nil
    }

    private static func defaultKeychainServiceNames() -> [String] {
        var serviceNames = ["Claude Code-credentials"]

        if
            let configDirectory = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
            !configDirectory.isEmpty,
            let hash = sha256Prefix(for: configDirectory)
        {
            serviceNames.insert("Claude Code-credentials-\(hash)", at: 0)
        }

        return serviceNames
    }

    private static func accountName() -> String {
        ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
    }

    private static func sha256Prefix(for value: String) -> String? {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(8)
            .description
        #else
        return nil
        #endif
    }

    private static func keychainCredentialData(serviceName: String) throws -> Data? {
        #if canImport(Security)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: accountName(),
            kSecAttrService: serviceName,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw ClaudeAuthTokenStoreError.unreadableCredentials
            }

            return data
        case errSecItemNotFound:
            return nil
        default:
            throw ClaudeAuthTokenStoreError.unreadableCredentials
        }
        #else
        return nil
        #endif
    }

    private static func writeKeychainCredentialData(_ data: Data, serviceName: String) throws {
        #if canImport(Security)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: accountName(),
            kSecAttrService: serviceName
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

            guard addStatus == errSecSuccess else {
                throw ClaudeAuthTokenStoreError.credentialsNotWritable
            }
        default:
            throw ClaudeAuthTokenStoreError.credentialsNotWritable
        }
        #else
        throw ClaudeAuthTokenStoreError.credentialsNotWritable
        #endif
    }

    private static func credentialRecord(from data: Data, source: ClaudeCredentialSource) throws -> ClaudeCredentialRecord {
        let credentialsData = decodedHexData(from: data) ?? data

        guard let root = try? JSONSerialization.jsonObject(with: credentialsData) as? [String: Any] else {
            throw ClaudeAuthTokenStoreError.unreadableCredentials
        }

        return ClaudeCredentialRecord(root: root, source: source)
    }

    private static func serializedCredentials(from root: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(root) else {
            throw ClaudeAuthTokenStoreError.credentialsNotWritable
        }

        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private static func oauthCredential(from record: ClaudeCredentialRecord) -> ClaudeOAuthCredential? {
        let root = record.root
        let oauth = root["claudeAiOauth"] as? [String: Any] ?? root

        guard let accessToken = tokenValue(named: "accessToken", in: oauth, fallback: root) else {
            return nil
        }

        return ClaudeOAuthCredential(
            accessToken: accessToken,
            refreshToken: tokenValue(named: "refreshToken", in: oauth, fallback: root),
            expiresAt: dateValue(named: "expiresAt", in: oauth, fallback: root),
            scopes: scopesValue(named: "scopes", in: oauth, fallback: root),
            subscriptionType: stringValue(named: "subscriptionType", in: oauth, fallback: root),
            rateLimitTier: stringValue(named: "rateLimitTier", in: oauth, fallback: root),
            record: record
        )
    }

    private static func tokenValue(
        named key: String,
        in dictionary: [String: Any],
        fallback: [String: Any]
    ) -> String? {
        stringValue(named: key, in: dictionary, fallback: fallback).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func stringValue(
        named key: String,
        in dictionary: [String: Any],
        fallback: [String: Any]
    ) -> String? {
        dictionary[key] as? String ?? fallback[key] as? String
    }

    private static func scopesValue(
        named key: String,
        in dictionary: [String: Any],
        fallback: [String: Any]
    ) -> [String] {
        if let scopes = dictionary[key] as? [String] {
            return scopes
        }

        if let scopes = fallback[key] as? [String] {
            return scopes
        }

        if let scopes = stringValue(named: key, in: dictionary, fallback: fallback) {
            return scopes.split(separator: " ").map(String.init)
        }

        return []
    }

    private static func dateValue(
        named key: String,
        in dictionary: [String: Any],
        fallback: [String: Any]
    ) -> Date? {
        date(from: dictionary[key]) ?? date(from: fallback[key])
    }

    private static func date(from value: Any?) -> Date? {
        if let value = value as? Date {
            return value
        }

        if let value = value as? Double {
            return date(fromTimestamp: value)
        }

        if let value = value as? Int {
            return date(fromTimestamp: Double(value))
        }

        if let value = value as? String {
            if let timestamp = Double(value) {
                return date(fromTimestamp: timestamp)
            }

            return ISO8601DateFormatter().date(from: value)
        }

        return nil
    }

    private static func date(fromTimestamp timestamp: Double) -> Date {
        if timestamp > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: timestamp / 1_000)
        }

        return Date(timeIntervalSince1970: timestamp)
    }

    private static func decodedHexData(from data: Data) -> Data? {
        guard
            let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !string.isEmpty,
            string.count.isMultiple(of: 2),
            string.unicodeScalars.allSatisfy(isHexadecimalDigit)
        else {
            return nil
        }

        var decoded = Data(capacity: string.count / 2)
        var index = string.startIndex

        while index < string.endIndex {
            let nextIndex = string.index(index, offsetBy: 2)
            guard let byte = UInt8(string[index..<nextIndex], radix: 16) else {
                return nil
            }

            decoded.append(byte)
            index = nextIndex
        }

        return decoded
    }

    private static func isHexadecimalDigit(_ scalar: UnicodeScalar) -> Bool {
        (48...57).contains(scalar.value)
            || (65...70).contains(scalar.value)
            || (97...102).contains(scalar.value)
    }
}

private struct ClaudeCredentialRecord {
    let root: [String: Any]
    let source: ClaudeCredentialSource
}

private enum ClaudeCredentialSource {
    case keychain(serviceName: String)
    case file(URL)
    case injected
}
