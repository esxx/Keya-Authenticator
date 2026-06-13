import Foundation

// MARK: - Keychain Access Group Migration

extension KeychainManager {
    /// UserDefaults key for the migration sentinel.
    /// Bump the suffix (v2, v3, …) if a future migration is needed.
    static let migrationV1Key = "keychainAccessGroupMigration_v1"

    /// Defensive migration that re-saves every token Keychain item once after the
    /// `keychain-access-groups` entitlement is added.
    ///
    /// **Why this exists (and why it is effectively a no-op).**
    /// The app's private Keychain group (`<TeamID>.ee.exx.KeyaAuthenticator`) is
    /// identical to the shared group name declared in the entitlement.  iOS
    /// preserves all existing items across the entitlement change, so tokens are
    /// already readable by the extension without any migration.  `saveToken()` does
    /// not set `kSecAttrAccessGroup`, so each item stays in the same slot.  In
    /// practice this performs a delete-then-add into the same group — a safe no-op
    /// that keeps the sentinel pattern in place for any future migration that does
    /// need to move items.
    ///
    /// **What actually enables AutoFill** is the Xcode Signing & Capabilities
    /// wiring: both targets must declare the same `keychain-access-groups` entry
    /// (`ee.exx.KeyaAuthenticator`).
    ///
    /// **Crash safety.**
    /// All tokens are snapshotted into memory before any delete-then-add cycle.
    /// The sentinel is written only after every token succeeds; any failure leaves
    /// it unset so the migration retries on the next foreground launch.
    static func migrateTokensToSharedKeychainGroupIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationV1Key) else { return }

        // Snapshot all tokens into memory before touching individual items.
        // loadAllTokens() returns [] on errSecItemNotFound — that's fine and treated
        // as "nothing to migrate".
        let tokens: [Token]
        do {
            tokens = try loadAllTokens()
        } catch {
            // Keychain unavailable (e.g. device still locked on cold boot).
            // Leave the sentinel unset and retry on the next foreground launch.
            return
        }

        var allSucceeded = true
        for token in tokens {
            do {
                // saveToken() does delete-then-add, which re-writes the item into
                // the app's current default access group — the shared one declared
                // in the keychain-access-groups entitlement.
                try saveToken(token)
            } catch {
                allSucceeded = false
                // Continue with remaining tokens: partial migration is recoverable
                // because the sentinel is not written and the loop retries next launch.
            }
        }

        if allSucceeded {
            UserDefaults.standard.set(true, forKey: migrationV1Key)
        }
    }
}
