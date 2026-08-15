import XCTest
@testable import Keya_Authenticator

final class EditTokenViewModelTests: XCTestCase {

    private var tokenStore: TokenStore!
    private var settings: AppSettings!

    // MARK: - Helpers

    private func makeToken(name: String, secret: String = "shared-secret-key-1", digits: Int = 6) -> Token {
        var secretData = Data(secret.utf8)
        while secretData.count < 10 { secretData.append(0) }
        return Token(name: name, issuer: "Issuer", secret: secretData,
                     algorithm: .sha1, digits: digits, type: .totp, period: 30, counter: nil)
    }

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        try? KeychainManager.deleteAllTokens()
        UserDefaults.standard.removeObject(forKey: "tokenSortOrder")
        tokenStore = TokenStore()
        settings = AppSettings()
    }

    override func tearDown() {
        try? KeychainManager.deleteAllTokens()
        UserDefaults.standard.removeObject(forKey: "tokenSortOrder")
        tokenStore = nil
        settings = nil
        super.tearDown()
    }

    // MARK: - No conflict: normal edits save immediately

    func testSaveWithoutContentConflictSucceedsImmediately() async throws {
        let token = makeToken(name: "GitHub")
        try tokenStore.update([token])
        let viewModel = EditTokenViewModel(tokenStore: tokenStore, settings: settings, token: token)
        viewModel.name = "GitHub Renamed"

        let success = await viewModel.saveToken()

        XCTAssertTrue(success)
        XCTAssertNil(viewModel.pendingDuplicateAdd)
        XCTAssertEqual(tokenStore.tokens.first?.name, "GitHub Renamed")
    }

    // MARK: - Editing into a collision with a different existing token

    func testSaveIntoContentConflictDoesNotPersistImmediately() async throws {
        let colliding = makeToken(name: "Discord", digits: 8)
        let edited = makeToken(name: "GitHub", digits: 6)
        try tokenStore.update([colliding, edited])

        let viewModel = EditTokenViewModel(tokenStore: tokenStore, settings: settings, token: edited)
        viewModel.digits = 8 // same secret+algorithm+period as `colliding`: now collides by contentKey

        let success = await viewModel.saveToken()

        XCTAssertFalse(success)
        XCTAssertNotNil(viewModel.pendingDuplicateAdd)
        XCTAssertEqual(viewModel.pendingDuplicateAdd?.existingName, "Discord")
        XCTAssertEqual(tokenStore.tokens.first(where: { $0.id == edited.id })?.digits, 6,
                       "The unsaved edit must not have been persisted")
    }

    func testConfirmPendingDuplicateSavePersistsTheEdit() async throws {
        let colliding = makeToken(name: "Discord", digits: 8)
        let edited = makeToken(name: "GitHub", digits: 6)
        try tokenStore.update([colliding, edited])

        let viewModel = EditTokenViewModel(tokenStore: tokenStore, settings: settings, token: edited)
        viewModel.digits = 8
        _ = await viewModel.saveToken()

        let success = await viewModel.confirmPendingDuplicateSave()

        XCTAssertTrue(success)
        XCTAssertNil(viewModel.pendingDuplicateAdd)
        XCTAssertEqual(tokenStore.tokens.count, 2, "Both tokens must coexist after confirmation")
        XCTAssertEqual(tokenStore.tokens.first(where: { $0.id == edited.id })?.digits, 8,
                       "The edit must be persisted after explicit confirmation")
    }

    func testCancelPendingDuplicateSaveDiscardsTheEdit() async throws {
        let colliding = makeToken(name: "Discord", digits: 8)
        let edited = makeToken(name: "GitHub", digits: 6)
        try tokenStore.update([colliding, edited])

        let viewModel = EditTokenViewModel(tokenStore: tokenStore, settings: settings, token: edited)
        viewModel.digits = 8
        _ = await viewModel.saveToken()

        viewModel.cancelPendingDuplicateSave()

        XCTAssertNil(viewModel.pendingDuplicateAdd)
        XCTAssertEqual(tokenStore.tokens.first(where: { $0.id == edited.id })?.digits, 6,
                       "Cancelling must leave the stored token unchanged")
    }
}
