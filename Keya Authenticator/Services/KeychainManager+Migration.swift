import Foundation

// MARK: - Keychain Access Group Migration

extension KeychainManager {
    static let migrationV1Key = "keychainAccessGroupMigration_v1"

    static func migrateTokensToSharedKeychainGroupIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationV1Key) else { return }

        let tokens: [Token]
        do {
            tokens = try loadAllTokens()
        } catch {
            return
        }

        var allSucceeded = true
        for token in tokens {
            do {
                try saveToken(token)
            } catch {
                allSucceeded = false
            }
        }

        if allSucceeded {
            UserDefaults.standard.set(true, forKey: migrationV1Key)
        }
    }
}
