import Security
import XCTest
@testable import Keya_Authenticator

/// Tests for AppSettings loading and Keychain/UserDefaults consistency.
final class AppSettingsTests: XCTestCase {

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        // Clean slate before each test
        KeychainManager.deleteSecuritySettings()
        KeychainManager.deleteBiometricFingerprint()
        UserDefaults.standard.removeObject(forKey: "biometricActivated")
        // Write the install sentinel so clearStaleKeychainIfReinstalled()
        // treats each test as a normal (non-fresh-install) launch.
        writeInstallSentinel()
    }

    override func tearDown() {
        KeychainManager.deleteSecuritySettings()
        KeychainManager.deleteBiometricFingerprint()
        UserDefaults.standard.removeObject(forKey: "biometricActivated")
        super.tearDown()
    }

    // MARK: - Reinstall desync (regression for Face ID bug)

    /// Regression test: Keychain/UserDefaults desync after app delete + reinstall.
    ///
    /// iOS does NOT wipe the Keychain when an app is deleted; UserDefaults is wiped.
    /// Before the fix, this left `useBiometricAuthentication = true` in the Keychain
    /// while `biometricActivated` was absent (false) in UserDefaults, making the
    /// Face ID toggle appear ON but never actually prompting for Face ID.
    ///
    /// After the fix, both flags must agree: if `biometricActivated` is false the
    /// Keychain value is ignored and `useBiometricAuthentication` is reset to false.
    func testReinstall_keychainHasBiometricTrue_userDefaultsHasNoBiometricActivated_resetsToFalse() throws {
        // Arrange — simulate Keychain state that survived a delete + reinstall
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(
                isAuthenticationEnabled: true,
                useBiometricAuthentication: true,   // ← stale Keychain value
                lockGracePeriod: 30
            )
        )
        // UserDefaults has no biometricActivated key (wiped on uninstall)
        UserDefaults.standard.removeObject(forKey: "biometricActivated")

        // Act — simulate app launch after reinstall
        let settings = AppSettings()

        // Assert — Face ID toggle must show OFF; user must re-enable
        XCTAssertFalse(
            settings.useBiometricAuthentication,
            "useBiometricAuthentication must be false when biometricActivated is absent — " +
            "stale Keychain value from before reinstall must not activate Face ID silently"
        )
        XCTAssertFalse(
            settings.biometricActivated,
            "biometricActivated must remain false (UserDefaults was wiped on reinstall)"
        )
    }

    // MARK: - Normal (non-reinstall) cases

    /// Both flags true → biometric stays enabled (happy path, no regression).
    func testNormalLaunch_bothFlagsTrue_biometricStaysEnabled() throws {
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(
                isAuthenticationEnabled: true,
                useBiometricAuthentication: true,
                lockGracePeriod: 30
            )
        )
        UserDefaults.standard.set(true, forKey: "biometricActivated")

        let settings = AppSettings()

        XCTAssertTrue(settings.useBiometricAuthentication)
        XCTAssertTrue(settings.biometricActivated)
    }

    /// Both flags false → biometric stays disabled.
    func testNormalLaunch_bothFlagsFalse_biometricStaysDisabled() throws {
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(
                isAuthenticationEnabled: false,
                useBiometricAuthentication: false,
                lockGracePeriod: 30
            )
        )
        UserDefaults.standard.set(false, forKey: "biometricActivated")

        let settings = AppSettings()

        XCTAssertFalse(settings.useBiometricAuthentication)
        XCTAssertFalse(settings.biometricActivated)
    }

    /// Keychain says false, UserDefaults says true (opposite desync) →
    /// useBiometricAuthentication follows Keychain (false), toggle shows OFF.
    func testOppositeDesync_keychainFalse_userDefaultsTrue_biometricOff() throws {
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(
                isAuthenticationEnabled: true,
                useBiometricAuthentication: false,
                lockGracePeriod: 30
            )
        )
        UserDefaults.standard.set(true, forKey: "biometricActivated")

        let settings = AppSettings()

        XCTAssertFalse(
            settings.useBiometricAuthentication,
            "AND logic: false && true must be false"
        )
    }

    // MARK: - lockGracePeriod preserved through sync

    /// The biometric sync must not corrupt lockGracePeriod stored in the Keychain.
    func testReinstallDesync_lockGracePeriodPreserved() throws {
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(
                isAuthenticationEnabled: true,
                useBiometricAuthentication: true,
                lockGracePeriod: 5           // non-default value
            )
        )
        UserDefaults.standard.removeObject(forKey: "biometricActivated")

        let settings = AppSettings()

        XCTAssertEqual(settings.lockGracePeriod, 5,
                       "lockGracePeriod must survive the biometric sync correction")
    }

    // MARK: - Helpers

    private func writeInstallSentinel() {
        let del: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Constants.keychainService,
            kSecAttrAccount: "app.installSentinel",
        ]
        SecItemDelete(del as CFDictionary)
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Constants.keychainService,
            kSecAttrAccount: "app.installSentinel",
            kSecValueData: Data([1]),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }
}
