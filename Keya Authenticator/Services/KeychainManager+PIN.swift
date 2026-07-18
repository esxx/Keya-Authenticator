import CommonCrypto
import Foundation
import LocalAuthentication
import Security

// MARK: - PIN Security

extension KeychainManager {
    // MARK: Types

    struct LockoutState: Codable {
        var failedAttempts: Int
        var lockoutUntil: Date?
        var lastFailedAttempt: Date?
    }

    private struct PINData: Codable {
        let salt: Data
        let hash: Data
        let iterations: Int
    }

    private static let pinIterations = 100_000
    private static let pinAccount = "app_pin"

    // MARK: - PIN Storage

    static func savePIN(_ pin: String) throws {
        var salt = Data(count: 32)
        let saltResult = salt.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let ptr = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, 32, ptr)
        }
        guard saltResult == errSecSuccess else {
            throw TokenError.keychainError("PIN setup failed. Please try again.")
        }

        let hash = try derivePINHash(pin: pin, salt: salt, iterations: pinIterations)
        let pinData = PINData(salt: salt, hash: hash, iterations: pinIterations)
        let encoded = try JSONEncoder().encode(pinData)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: pinAccount,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: pinAccount,
            kSecAttrAccessible as String: accessibility,
            kSecValueData as String: encoded,
        ]
        guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else {
            throw TokenError.keychainError("Your PIN couldn't be saved. Please try again.")
        }
    }

    static func verifyPIN(_ pin: String) throws -> Bool? {
        let query = makeQuery(account: pinAccount, matchLimit: kSecMatchLimitOne, returnData: true)
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw TokenError.keychainError("PIN verification failed. Please try again.")
        }
        guard let data = result as? Data else {
            throw TokenError.keychainError("Your PIN data appears to be corrupted. Please reset your PIN.")
        }

        let pinData = try JSONDecoder().decode(PINData.self, from: data)
        let candidateHash = try derivePINHash(pin: pin, salt: pinData.salt, iterations: pinData.iterations)
        return constantTimeCompare(candidateHash, pinData.hash)
    }

    static func isPINSet() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: pinAccount,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    static func deletePIN() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: pinAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenError.keychainError("Your PIN couldn't be removed. Please try again.")
        }
    }

    // MARK: - Lockout State

    static func saveLockoutState(_ state: LockoutState, account: String = "pin_lockout_state") throws {
        let encoded = try JSONEncoder().encode(state)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: accessibility,
            kSecValueData as String: encoded,
        ]
        guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else {
            throw TokenError.keychainError("Security state couldn't be saved. Please try again.")
        }
    }

    static func loadLockoutState(
        using authContext: LAContext? = nil,
        account: String = "pin_lockout_state"
    ) throws -> LockoutState {
        let query = makeQuery(
            account: account,
            matchLimit: kSecMatchLimitOne,
            returnData: true,
            authContext: authContext
        )
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return LockoutState(failedAttempts: 0, lockoutUntil: nil, lastFailedAttempt: nil)
        }
        guard status == errSecSuccess else {
            throw TokenError.keychainError("Security state is temporarily unavailable. Please try again.")
        }
        guard let data = result as? Data else {
            throw TokenError.keychainError("Security state is temporarily unavailable. Please try again.")
        }
        guard let state = try? JSONDecoder().decode(LockoutState.self, from: data) else {
            try? deleteLockoutState(account: account)
            return LockoutState(
                failedAttempts: 0,
                lockoutUntil: Date().addingTimeInterval(5 * 60),
                lastFailedAttempt: Date()
            )
        }
        return state
    }

    static func deleteLockoutState(account: String = "pin_lockout_state") throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - PBKDF2 Key Derivation

    private static func derivePINHash(pin: String, salt: Data, iterations: Int) throws -> Data {
        guard let pinData = pin.data(using: .utf8) else {
            throw TokenError.keychainError("PIN setup failed. Please try again.")
        }
        var derivedKey = Data(count: 32)
        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes -> Int32 in
            pinData.withUnsafeBytes { pinBytes -> Int32 in
                salt.withUnsafeBytes { saltBytes -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pinBytes.baseAddress, pinData.count,
                        saltBytes.baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress, 32
                    )
                }
            }
        }
        guard status == errSecSuccess else {
            throw TokenError.keychainError("PIN setup failed. Please try again.")
        }
        return derivedKey
    }

    private static func constantTimeCompare(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        for i in 0 ..< a.count {
            result |= a[i] ^ b[i]
        }
        return result == 0
    }
}
