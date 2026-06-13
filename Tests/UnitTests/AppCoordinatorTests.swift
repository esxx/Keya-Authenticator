import XCTest
@testable import Keya_Authenticator

final class AppCoordinatorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        try? KeychainManager.deleteAllTokens()
        UserDefaults.standard.removeObject(forKey: KeychainManager.migrationV1Key)
    }

    override func tearDown() {
        try? KeychainManager.deleteAllTokens()
        UserDefaults.standard.removeObject(forKey: KeychainManager.migrationV1Key)
        super.tearDown()
    }

    // MARK: - Pending URL on no-auth path

    /// When PIN is set but authentication is disabled, determineInitialState() goes
    /// directly to .main without calling completeUnlock(). Before the fix, any URL
    /// that arrived during .loading was silently dropped. After the fix it is forwarded
    /// to MainContentViewModel immediately.
    func testDetermineInitialState_noAuth_consumesPendingURL() throws {
        // First AppSettings.init() writes the installSentinel so the second init
        // does not wipe the PIN and security settings we are about to save.
        _ = AppSettings()

        try KeychainManager.savePIN("123456")
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(
                isAuthenticationEnabled: false,
                useBiometricAuthentication: false,
                lockGracePeriod: nil
            )
        )

        // Second init reads isAuthenticationEnabled = false from Keychain.
        let coordinator = AppCoordinator(
            tokenStore: TokenStore(),
            authenticationManager: AuthenticationManager(),
            settings: AppSettings()
        )

        // URL arrives before the app state machine runs (cold launch via URL).
        let url = URL(string: "otpauth://totp/Test:user@example.com?secret=JBSWY3DPEHPK3PXP")!
        coordinator.handleIncomingURL(url)

        // State machine runs — this is the path that was missing processPendingURL().
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

    /// Control: when no pending URL exists, determineInitialState() must NOT open
    /// the add sheet on the no-auth path.
    func testDetermineInitialState_noAuth_noPendingURL_doesNotOpenSheet() throws {
        _ = AppSettings()

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
