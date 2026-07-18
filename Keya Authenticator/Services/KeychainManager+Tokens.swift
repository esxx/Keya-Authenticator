import Foundation
import LocalAuthentication
import Security

// MARK: - Token Storage

extension KeychainManager {
    static func saveToken(_ token: Token) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let tokenData = try encoder.encode(token)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: token.id.uuidString,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: token.id.uuidString,
            kSecAttrAccessible as String: accessibility,
            kSecValueData as String: tokenData,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TokenError.keychainError(String(localized: "Your token couldn't be saved. Please try again."))
        }
    }

    static func loadAllTokens(using authContext: LAContext? = nil) throws -> [Token] {
        let query = makeQuery(
            matchLimit: kSecMatchLimitAll,
            returnData: true,
            returnAttributes: true,
            authContext: authContext
        )
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw TokenError
                .keychainError(String(localized: "Your tokens couldn't be loaded. Try locking and unlocking the app."))
        }
        guard let items = result as? [[String: Any]] else {
            throw TokenError.keychainError(String(localized: "Your vault data appears to be corrupted."))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reservedAccounts = Token.reservedKeychainAccounts

        var allTokens: [Token] = []
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String,
               reservedAccounts.contains(account)
            {
                continue
            }
            guard let data = item[kSecValueData as String] as? Data else { continue }
            if let token = try? decoder.decode(Token.self, from: data) {
                allTokens.append(token)
            }
        }

        return deduplicated(allTokens)
    }

    static func updateToken(_ token: Token) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let tokenData = try encoder.encode(token)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: token.id.uuidString,
        ]
        let attributes: [String: Any] = [kSecValueData as String: tokenData]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status != errSecSuccess {
            try deleteToken(id: token.id)
            try saveToken(token)
        }
    }

    static func deleteToken(id: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenError.keychainError(String(localized: "The token couldn't be deleted. Please try again."))
        }
    }

    static func deleteAllTokens() throws {
        let listQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let listStatus = SecItemCopyMatching(listQuery as CFDictionary, &result)

        if listStatus == errSecItemNotFound {
            return
        }
        guard listStatus == errSecSuccess, let items = result as? [[String: Any]] else {
            throw TokenError.keychainError("Your tokens couldn't be deleted. Please try again.")
        }

        let reserved = Token.reservedKeychainAccounts
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  !reserved.contains(account)
            else { continue }
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let status = SecItemDelete(deleteQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw TokenError.keychainError("Your tokens couldn't be deleted. Please try again.")
            }
        }
    }

    // MARK: - Deduplication

    private static func deduplicated(_ tokens: [Token]) -> [Token] {
        var bestByContent: [String: Token] = [:]
        var orphanIDs: [UUID] = []

        for token in tokens {
            if let existing = bestByContent[token.contentKey] {
                if token.updatedAt > existing.updatedAt {
                    orphanIDs.append(existing.id)
                    bestByContent[token.contentKey] = token
                } else {
                    orphanIDs.append(token.id)
                }
            } else {
                bestByContent[token.contentKey] = token
            }
        }
        orphanIDs.forEach { try? deleteToken(id: $0) }
        return Array(bestByContent.values).sorted { $0.createdAt < $1.createdAt }
    }
}
