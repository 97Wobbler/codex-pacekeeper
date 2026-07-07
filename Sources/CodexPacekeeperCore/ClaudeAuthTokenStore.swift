import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(LocalAuthentication)
import LocalAuthentication
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

public enum ClaudeKeychainPromptPolicy: Equatable {
    case allow
    case disallow
}

public struct ClaudeOAuthCredential: Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let scopes: [String]
    public let subscriptionType: String?
    public let rateLimitTier: String?

    fileprivate let record: ClaudeCredentialRecord

    fileprivate var storageRoot: [String: Any] {
        storageRoot()
    }

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

    fileprivate func storageRoot(
        accessToken: String? = nil,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        scopes: [String]? = nil
    ) -> [String: Any] {
        var oauth: [String: Any] = [
            "accessToken": accessToken ?? self.accessToken,
            "scopes": scopes ?? self.scopes
        ]

        if let refreshToken = refreshToken ?? self.refreshToken {
            oauth["refreshToken"] = refreshToken
        }

        if let expiresAt = expiresAt ?? self.expiresAt {
            oauth["expiresAt"] = Int(expiresAt.timeIntervalSince1970 * 1_000)
        }

        if let subscriptionType {
            oauth["subscriptionType"] = subscriptionType
        }

        if let rateLimitTier {
            oauth["rateLimitTier"] = rateLimitTier
        }

        return ["claudeAiOauth": oauth]
    }
}

public final class ClaudeAuthTokenStore {
    private let credentialsFileURL: URL
    private let keychainCredentialRecord: (ClaudeKeychainPromptPolicy) throws -> ClaudeCredentialRecord?

    public convenience init(
        credentialsFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json", isDirectory: false)
    ) {
        self.init(
            credentialsFileURL: credentialsFileURL,
            keychainCredentialRecord: { promptPolicy in
                try Self.defaultKeychainCredentialRecord(promptPolicy: promptPolicy)
            }
        )
    }

    init(
        credentialsFileURL: URL,
        keychainCredentialData: @escaping () throws -> Data?
    ) {
        self.credentialsFileURL = credentialsFileURL
        self.keychainCredentialRecord = { _ in
            guard let data = try keychainCredentialData() else {
                return nil
            }

            return try Self.credentialRecord(from: data, source: .injected)
        }
    }

    private init(
        credentialsFileURL: URL,
        keychainCredentialRecord: @escaping (ClaudeKeychainPromptPolicy) throws -> ClaudeCredentialRecord?
    ) {
        self.credentialsFileURL = credentialsFileURL
        self.keychainCredentialRecord = keychainCredentialRecord
    }

    public func accessToken() throws -> String {
        try oauthCredential().accessToken
    }

    public func oauthCredential(
        promptPolicy: ClaudeKeychainPromptPolicy = .allow
    ) throws -> ClaudeOAuthCredential {
        let record = try credentialRecord(promptPolicy: promptPolicy)
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

    private func credentialRecord(promptPolicy: ClaudeKeychainPromptPolicy) throws -> ClaudeCredentialRecord {
        var foundCredentials = false
        var unreadableCredentials = false

        do {
            if let record = try keychainCredentialRecord(promptPolicy) {
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

    private static func defaultKeychainCredentialRecord(
        promptPolicy: ClaudeKeychainPromptPolicy
    ) throws -> ClaudeCredentialRecord? {
        for serviceName in defaultKeychainServiceNames() {
            if let data = try keychainCredentialData(serviceName: serviceName, promptPolicy: promptPolicy) {
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

    fileprivate static func keychainCredentialData(
        serviceName: String,
        promptPolicy: ClaudeKeychainPromptPolicy = .allow
    ) throws -> Data? {
        #if canImport(Security)
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: accountName(),
            kSecAttrService: serviceName,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true
        ]

        #if canImport(LocalAuthentication)
        let authenticationContext = LAContext()
        if promptPolicy == .disallow {
            authenticationContext.interactionNotAllowed = true
            query[kSecUseAuthenticationContext] = authenticationContext
        }
        #endif

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

    fileprivate static func writeKeychainCredentialData(_ data: Data, serviceName: String) throws {
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

    fileprivate static func deleteKeychainCredentialData(serviceName: String) throws {
        #if canImport(Security)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: accountName(),
            kSecAttrService: serviceName
        ]
        let status = SecItemDelete(query as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw ClaudeAuthTokenStoreError.credentialsNotWritable
        }
        #else
        throw ClaudeAuthTokenStoreError.credentialsNotWritable
        #endif
    }

    fileprivate static func credentialRecord(from data: Data, source: ClaudeCredentialSource) throws -> ClaudeCredentialRecord {
        let credentialsData = decodedHexData(from: data) ?? data

        guard let root = try? JSONSerialization.jsonObject(with: credentialsData) as? [String: Any] else {
            throw ClaudeAuthTokenStoreError.unreadableCredentials
        }

        return ClaudeCredentialRecord(root: root, source: source)
    }

    fileprivate static func serializedCredentials(from root: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(root) else {
            throw ClaudeAuthTokenStoreError.credentialsNotWritable
        }

        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    fileprivate static func oauthCredential(from record: ClaudeCredentialRecord) -> ClaudeOAuthCredential? {
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

public final class PacekeeperClaudeCredentialStore {
    public static let defaultServiceName = "Codex Pacekeeper Claude Credentials"

    private let serviceName: String
    private let keychainCredentialData: (String, ClaudeKeychainPromptPolicy) throws -> Data?
    private let writeKeychainCredentialData: (Data, String) throws -> Void
    private let deleteKeychainCredentialData: (String) throws -> Void

    public convenience init(serviceName: String = PacekeeperClaudeCredentialStore.defaultServiceName) {
        self.init(
            serviceName: serviceName,
            keychainCredentialData: { serviceName, promptPolicy in
                try ClaudeAuthTokenStore.keychainCredentialData(
                    serviceName: serviceName,
                    promptPolicy: promptPolicy
                )
            },
            writeKeychainCredentialData: { data, serviceName in
                try ClaudeAuthTokenStore.writeKeychainCredentialData(data, serviceName: serviceName)
            },
            deleteKeychainCredentialData: { serviceName in
                try ClaudeAuthTokenStore.deleteKeychainCredentialData(serviceName: serviceName)
            }
        )
    }

    init(
        serviceName: String = PacekeeperClaudeCredentialStore.defaultServiceName,
        keychainCredentialData: @escaping (String, ClaudeKeychainPromptPolicy) throws -> Data?,
        writeKeychainCredentialData: @escaping (Data, String) throws -> Void,
        deleteKeychainCredentialData: @escaping (String) throws -> Void
    ) {
        self.serviceName = serviceName
        self.keychainCredentialData = keychainCredentialData
        self.writeKeychainCredentialData = writeKeychainCredentialData
        self.deleteKeychainCredentialData = deleteKeychainCredentialData
    }

    public func oauthCredential(
        promptPolicy: ClaudeKeychainPromptPolicy = .allow
    ) throws -> ClaudeOAuthCredential {
        guard let data = try keychainCredentialData(serviceName, promptPolicy) else {
            throw ClaudeAuthTokenStoreError.credentialsMissing
        }

        let record = try ClaudeAuthTokenStore.credentialRecord(
            from: data,
            source: .keychain(serviceName: serviceName)
        )

        guard let credential = ClaudeAuthTokenStore.oauthCredential(from: record) else {
            throw ClaudeAuthTokenStoreError.accessTokenMissing
        }

        return credential
    }

    public func saveCredential(_ credential: ClaudeOAuthCredential) throws -> ClaudeOAuthCredential {
        try saveRoot(credential.storageRoot)
    }

    public func saveRefreshResult(
        _ refreshResult: ClaudeOAuthRefreshResult,
        for credential: ClaudeOAuthCredential
    ) throws -> ClaudeOAuthCredential {
        let root = credential.storageRoot(
            accessToken: refreshResult.accessToken,
            refreshToken: refreshResult.refreshToken ?? credential.refreshToken,
            expiresAt: refreshResult.expiresAt,
            scopes: refreshResult.scopes
        )

        return try saveRoot(root)
    }

    public func deleteCredential() throws {
        try deleteKeychainCredentialData(serviceName)
    }

    private func saveRoot(_ root: [String: Any]) throws -> ClaudeOAuthCredential {
        let data = try ClaudeAuthTokenStore.serializedCredentials(from: root)
        try writeKeychainCredentialData(data, serviceName)

        let record = try ClaudeAuthTokenStore.credentialRecord(
            from: data,
            source: .keychain(serviceName: serviceName)
        )

        guard let credential = ClaudeAuthTokenStore.oauthCredential(from: record) else {
            throw ClaudeAuthTokenStoreError.accessTokenMissing
        }

        return credential
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
