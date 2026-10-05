import Security
import XCTest
@testable import Keya_Authenticator

final class AppCoordinatorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        cleanKeychain()
        UserDefaults.standard.removeObject(forKey: KeychainManager.migrationV1Key)
    }

    override func tearDown() {
        cleanKeychain()
        UserDefaults.standard.removeObject(forKey: KeychainManager.migrationV1Key)
        super.tearDown()
    }

    private func cleanKeychain() {
        try? KeychainManager.deleteAllTokens()
        try? KeychainManager.deletePIN()
        KeychainManager.deleteSecuritySettings()
        try? KeychainManager.deleteLockoutState(account: KeychainManager.pinLockoutAccount)
    }

    // MARK: - Reset

    @MainActor
    func testResetEverything_deletesTokensAndPIN_andOpensPINSetup() throws {
        try KeychainManager.savePIN("123456")
        let tokenStore = TokenStore()
        let secret = Data("reset-test-secret-1".utf8)
        try tokenStore.update([Token(name: "A", secret: secret), Token(name: "B", secret: secret + Data([1]))])

        let coordinator = AppCoordinator(
            tokenStore: tokenStore,
            authenticationManager: AuthenticationManager(),
            settings: AppSettings()
        )
        try coordinator.resetEverything()

        XCTAssertEqual(coordinator.appState, .pinSetup)
        XCTAssertTrue(tokenStore.tokens.isEmpty)
        XCTAssertTrue(try KeychainManager.loadAllTokens().isEmpty)
        XCTAssertEqual(KeychainManager.pinPresence(), .notSet)
    }

    @MainActor
    func testResetEverything_keepsInstallSentinel() throws {
        _ = AppSettings()
        let sentinelQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.keychainService,
            kSecAttrAccount as String: "app.installSentinel",
        ]
        XCTAssertEqual(SecItemCopyMatching(sentinelQuery as CFDictionary, nil), errSecSuccess)

        let tokenStore = TokenStore()
        let coordinator = AppCoordinator(
            tokenStore: tokenStore,
            authenticationManager: AuthenticationManager(),
            settings: AppSettings()
        )
        try coordinator.resetEverything()

        XCTAssertEqual(SecItemCopyMatching(sentinelQuery as CFDictionary, nil), errSecSuccess,
                       "Reset must not delete the install sentinel, or the next launch looks like a fresh install")
    }

    // MARK: - Pending URL on no-auth path

    func testDetermineInitialState_noAuth_consumesPendingURL() throws {
        try KeychainManager.savePIN("123456")
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(
                isAuthenticationEnabled: false,
                useBiometricAuthentication: false,
                lockGracePeriod: nil
            )
        )

        let coordinator = AppCoordinator(
            tokenStore: TokenStore(),
            authenticationManager: AuthenticationManager(),
            settings: AppSettings()
        )

        let url = URL(string: "otpauth://totp/Test:user@example.com?secret=JBSWY3DPEHPK3PXP")!
        coordinator.handleIncomingURL(url)

        coordinator.determineInitialState()

        XCTAssertTrue(
            coordinator.mainContentViewModel.showingAddSheet,
            "Add sheet must open after URL-triggered cold launch when auth is disabled"
        )
        XCTAssertNotNil(
            coordinator.mainContentViewModel.pendingOTPAuthURI,
            "Pending URI must be forwarded to the add sheet"
        )
    }

    func testDetermineInitialState_noAuth_noPendingURL_doesNotOpenSheet() throws {
        try KeychainManager.savePIN("123456")
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(
                isAuthenticationEnabled: false,
                useBiometricAuthentication: false,
                lockGracePeriod: nil
            )
        )

        let coordinator = AppCoordinator(
            tokenStore: TokenStore(),
            authenticationManager: AuthenticationManager(),
            settings: AppSettings()
        )

        coordinator.determineInitialState()

        XCTAssertFalse(
            coordinator.mainContentViewModel.showingAddSheet,
            "Add sheet must not open when there is no pending URL"
        )
    }
}
