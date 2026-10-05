import Foundation
import LocalAuthentication
import Security

// MARK: - Token Storage

extension KeychainManager {
    static func saveToken(_ token: Token) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let tokenData = try encoder.encode(token)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: token.id.uuidString,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: tokenData] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecAttrAccessible as String] = accessibility
            addQuery[kSecValueData as String] = tokenData
            guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else {
                throw TokenError.keychainError(String(localized: "Your token couldn't be saved. Please try again."))
            }
        } else {
            guard updateStatus == errSecSuccess else {
                throw TokenError.keychainError(String(localized: "Your token couldn't be saved. Please try again."))
            }
        }
    }

    static func loadAllTokens(using authContext: LAContext? = nil) throws -> [Token] {
        try loadAllTokensCountingUnreadable(using: authContext).tokens
    }

    static func loadAllTokensCountingUnreadable(
        using authContext: LAContext? = nil
    ) throws -> (tokens: [Token], unreadable: Int) {
        let query = makeQuery(
            matchLimit: kSecMatchLimitAll,
            returnData: true,
            returnAttributes: true,
            authContext: authContext
        )
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return ([], 0)
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
        var unreadable = 0
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String,
               reservedAccounts.contains(account)
            {
                continue
            }
            if let data = item[kSecValueData as String] as? Data,
               let token = try? decoder.decode(Token.self, from: data)
            {
                allTokens.append(token)
            } else {
                unreadable += 1
            }
        }

        return (allTokens.sorted { $0.createdAt < $1.createdAt }, unreadable)
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
            throw TokenError.keychainError(String(localized: "Your tokens couldn't be deleted. Please try again."))
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
                throw TokenError.keychainError(String(localized: "Your tokens couldn't be deleted. Please try again."))
            }
        }
    }
}
