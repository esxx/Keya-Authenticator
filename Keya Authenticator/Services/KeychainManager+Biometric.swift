import Foundation
import LocalAuthentication
import Security

// MARK: - Biometric Baseline Storage

extension KeychainManager {
    private static let biometricFingerprintAccount = "biometric_fingerprint"

    static func saveBiometricFingerprint(_ fingerprint: Data) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: biometricFingerprintAccount,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: biometricFingerprintAccount,
            kSecAttrAccessible as String: accessibility,
            kSecValueData as String: fingerprint,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func loadBiometricFingerprint() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: biometricFingerprintAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }

    static func deleteBiometricFingerprint() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: biometricFingerprintAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Security Settings

extension KeychainManager {
    struct SecuritySettings: Codable {
        var isAuthenticationEnabled: Bool
        var useBiometricAuthentication: Bool
        var lockGracePeriod: Int?
    }

    static let securitySettingsAccount = "security_settings"

    static func saveSecuritySettings(_ settings: SecuritySettings) throws {
        let encoded = try JSONEncoder().encode(settings)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: securitySettingsAccount,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: securitySettingsAccount,
            kSecAttrAccessible as String: accessibility,
            kSecValueData as String: encoded,
        ]
        guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else {
            throw TokenError.keychainError("Failed to save security settings.")
        }
    }

    static func loadSecuritySettings(using authContext: LAContext? = nil) -> SecuritySettings {
        let query = makeQuery(
            account: securitySettingsAccount,
            matchLimit: kSecMatchLimitOne,
            returnData: true,
            authContext: authContext
        )
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let settings = try? JSONDecoder().decode(SecuritySettings.self, from: data)
        else {
            let pinExists = isPINSet()
            return SecuritySettings(isAuthenticationEnabled: pinExists, useBiometricAuthentication: false)
        }
        return settings
    }

    static func deleteSecuritySettings() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: securitySettingsAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
