import CommonCrypto
import Foundation
import LocalAuthentication
import Security

enum KeychainManager {
    // MARK: - Shared Constants

    static let service = Constants.keychainService

    static let accessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    static let biometricPrompt = "Unlock your 2FA tokens"

    // MARK: - Lockout Account Keys

    static let pinLockoutAccount = "pin_lockout_state"

    static let biometricLockoutAccount = "biometric_lockout"

    // MARK: - Background Timestamp

    private static let backgroundTimestampAccount = "app_background_timestamp"

    @discardableResult
    static func saveBackgroundTimestamp(_ date: Date) -> Bool {
        let data = withUnsafeBytes(of: date.timeIntervalSinceReferenceDate) { Data($0) }
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: backgroundTimestampAccount,
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: backgroundTimestampAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func loadBackgroundTimestamp() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: backgroundTimestampAccount,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              data.count == MemoryLayout<Double>.size
        else { return nil }
        let interval = data.withUnsafeBytes { $0.load(as: Double.self) }
        return Date(timeIntervalSinceReferenceDate: interval)
    }

    static func deleteBackgroundTimestamp() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: backgroundTimestampAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Query Builder

    static func makeQuery(
        account: String? = nil,
        matchLimit: CFString = kSecMatchLimitAll,
        returnData: Bool = true,
        returnAttributes: Bool = false,
        authContext: LAContext? = nil
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: matchLimit,
        ]
        if let account {
            query[kSecAttrAccount as String] = account
        }
        if returnData {
            query[kSecReturnData as String] = true
        }
        if returnAttributes {
            query[kSecReturnAttributes as String] = true
        }
        if let context = authContext {
            context.localizedReason = biometricPrompt
            query[kSecUseAuthenticationContext as String] = context
        }
        return query
    }
}
