import XCTest
@testable import Keya_Authenticator

@MainActor
final class MainContentViewModelTests: XCTestCase {

    private var tokenStore: TokenStore!
    private var viewModel: MainContentViewModel!

    private func makeToken(name: String, type: TokenType = .totp) -> Token {
        var secret = Data(name.utf8)
        while secret.count < 10 { secret.append(0) }
        return Token(name: name, issuer: "Issuer", secret: secret, type: type,
                     period: type == .totp ? 30 : nil, counter: type == .hotp ? 0 : nil)
    }

    override func setUp() {
        super.setUp()
        try? KeychainManager.deleteAllTokens()
        UserDefaults.standard.removeObject(forKey: "tokenSortOrder")
        tokenStore = TokenStore()
        viewModel = MainContentViewModel(
            tokenStore: tokenStore, authenticationManager: AuthenticationManager(), settings: AppSettings()
        )
    }

    override func tearDown() {
        try? KeychainManager.deleteAllTokens()
        UserDefaults.standard.removeObject(forKey: "tokenSortOrder")
        viewModel = nil
        tokenStore = nil
        super.tearDown()
    }

    private func settle() async {
        for _ in 0 ..< 20 {
            await Task.yield()
        }
    }

    // MARK: - Changes made right after a favorite toggle

    func testFavoriteToggleKeepsHOTPStepMadeRightAfter() async throws {
        let favorite = makeToken(name: "Favorite")
        let counter = makeToken(name: "Counter", type: .hotp)
        try tokenStore.add([favorite, counter])

        viewModel.toggleFavorite(favorite)
        viewModel.incrementCounter(for: counter)
        await settle()

        XCTAssertEqual(tokenStore.tokens.first { $0.id == counter.id }?.counter, 1)
        XCTAssertEqual(try KeychainManager.loadAllTokens().first { $0.id == counter.id }?.counter, 1,
                       "A used HOTP code must not come back")
        XCTAssertEqual(tokenStore.tokens.first { $0.id == favorite.id }?.isFavorite, true)
    }

    func testFavoriteToggleKeepsDeleteMadeRightAfter() async throws {
        let favorite = makeToken(name: "Favorite")
        let removed = makeToken(name: "Removed")
        try tokenStore.add([favorite, removed])

        viewModel.toggleFavorite(favorite)
        viewModel.deleteToken(removed)
        await settle()

        XCTAssertFalse(tokenStore.tokens.contains { $0.id == removed.id })
        XCTAssertFalse(try KeychainManager.loadAllTokens().contains { $0.id == removed.id },
                       "A deleted token must stay deleted")
    }

    func testTwoQuickFavoriteTogglesCancelOut() async throws {
        let token = makeToken(name: "Twice")
        try tokenStore.add([token])

        viewModel.toggleFavorite(token)
        viewModel.toggleFavorite(token)
        await settle()

        XCTAssertEqual(tokenStore.tokens.first?.isFavorite, false)
        XCTAssertEqual(try KeychainManager.loadAllTokens().first?.isFavorite, false)
    }
}
