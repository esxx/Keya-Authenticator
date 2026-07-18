import XCTest
@testable import Keya_Authenticator

final class TokenStoreTests: XCTestCase {

    private var store: TokenStore!

    // MARK: - Helpers

    private let secret = "JBSWY3DPEHPK3PXP".base32DecodedData!

    private func makeToken(id: UUID = UUID(), name: String, issuer: String = "Issuer") -> Token {
        var uniqueSecret = Data(name.utf8)
        while uniqueSecret.count < 10 { uniqueSecret.append(0) }
        return Token(id: id, name: name, issuer: issuer,
                     secret: uniqueSecret, algorithm: .sha1,
                     digits: 6, type: .totp, period: 30, counter: nil)
    }

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        try? KeychainManager.deleteAllTokens()
        UserDefaults.standard.removeObject(forKey: "tokenSortOrder")
        store = TokenStore()
    }

    override func tearDown() {
        try? KeychainManager.deleteAllTokens()
        UserDefaults.standard.removeObject(forKey: "tokenSortOrder")
        store = nil
        super.tearDown()
    }

    // MARK: - Sort order

    func testMoveReordersTokensWithinSection() throws {
        let t1 = makeToken(name: "Alpha")
        let t2 = makeToken(name: "Beta")
        let t3 = makeToken(name: "Gamma")
        try store.update([t1, t2, t3])

        store.move(fromOffsets: IndexSet(integer: 1), toOffset: 0, in: store.tokens)

        XCTAssertEqual(store.tokens.map(\.name), ["Beta", "Alpha", "Gamma"])
    }

    func testSortOrderPersistsAcrossLoad() throws {
        let t1 = makeToken(name: "First")
        let t2 = makeToken(name: "Second")
        let t3 = makeToken(name: "Third")
        try store.update([t1, t2, t3])

        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0, in: store.tokens)
        let savedOrder = store.tokens.map(\.name)
        XCTAssertEqual(savedOrder.first, "Third", "Move should place Third first")

        store.clear()
        try store.load()
        XCTAssertEqual(store.tokens.map(\.name), savedOrder,
                       "Sort order should be preserved across a fresh load")
    }

    func testLoadThrowsWhenKeychainHasCorruptedEntry() throws {
        let corruptQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ee.exx.KeyaAuthenticator",
            kSecAttrAccount as String: UUID().uuidString,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: "not-json".data(using: .utf8)!,
        ]
        SecItemAdd(corruptQuery as CFDictionary, nil)

        XCTAssertNoThrow(try store.load(), "Corrupted individual entries must be skipped, not crash load()")

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ee.exx.KeyaAuthenticator",
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }

    // MARK: - Duplicate UUID regression (crash fix)

    func testDuplicateUUIDInUpdateDoesNotCrash() throws {
        let sharedID = UUID()
        let t1 = makeToken(id: sharedID, name: "Original")
        let t2 = makeToken(id: sharedID, name: "Duplicate")

        XCTAssertNoThrow(try store.update([t1, t2]),
                         "update() must not crash when two tokens share a UUID")
    }

    func testDuplicateUUIDMoveDoesNotCrash() throws {
        let t1 = makeToken(name: "Alpha")
        let t2 = makeToken(name: "Beta")
        let t3 = makeToken(name: "Gamma")
        try store.update([t1, t2, t3])

        XCTAssertNoThrow(
            store.move(fromOffsets: IndexSet(integer: 0), toOffset: 3, in: store.tokens),
            "move() must not crash"
        )
    }

    func testDuplicateUUIDCollapseToOne() throws {
        let sharedID = UUID()
        let t = makeToken(id: sharedID, name: "Token")
        XCTAssertNoThrow(try store.update([t, t]))
        XCTAssertEqual(store.tokens.filter { $0.id == sharedID }.count, 1,
                       "Tokens with a shared UUID must collapse to exactly one")
    }

    // MARK: - Content-based deduplication

    func testUpdateDeduplicatesIdenticalContent() throws {
        let t = makeToken(name: "Dupe")
        let copy = Token(id: UUID(), name: t.name, issuer: t.issuer,
                         secret: t.secret, algorithm: t.algorithm,
                         digits: t.digits, type: t.type, period: t.period, counter: nil)

        try store.update([t, copy])

        XCTAssertEqual(store.tokens.count, 1)
    }

    func testUpdatingExistingTokenBypassesContentDedup() throws {
        let original = makeToken(name: "Original")
        try store.update([original])

        var edited = original
        edited.name = "Renamed"
        try store.update([edited])

        XCTAssertEqual(store.tokens.count, 1)
        XCTAssertEqual(store.tokens.first?.name, "Renamed")
    }

    // MARK: - Delete

    func testDeleteRemovesCorrectToken() throws {
        let t1 = makeToken(name: "Keep")
        let t2 = makeToken(name: "Remove")
        try store.update([t1, t2])

        let removeIndex = store.tokens.firstIndex(where: { $0.name == "Remove" })!
        try store.delete(at: IndexSet(integer: removeIndex))

        XCTAssertEqual(store.tokens.count, 1)
        XCTAssertEqual(store.tokens.first?.name, "Keep")
    }

    func testDeleteAllEmptiesStore() throws {
        try store.update([makeToken(name: "A"), makeToken(name: "B")])
        store.deleteAll()
        XCTAssertTrue(store.tokens.isEmpty)
    }

    func testDeleteAllTokensPreservesReservedAccounts() throws {
        try KeychainManager.savePIN("123456")
        try store.update([makeToken(name: "A")])

        try KeychainManager.deleteAllTokens()

        XCTAssertTrue(KeychainManager.isPINSet(), "deleteAllTokens must not erase the PIN")
        XCTAssertTrue(try KeychainManager.loadAllTokens().isEmpty, "tokens must be gone")
        try KeychainManager.deletePIN()
    }

    // MARK: - Clear (security wipe)

    func testClearZeroesSecretsAndEmptiesStore() throws {
        try store.update([makeToken(name: "Sensitive")])
        store.clear()
        XCTAssertTrue(store.tokens.isEmpty)
    }

    // MARK: - isFavorite dedup regression

    func testUpdateNewerUpdatedAtWinsContentConflict() throws {
        let older = Token(
            name: "Service", issuer: "Corp",
            secret: secret, algorithm: .sha1,
            digits: 6, type: .totp, period: 30, counter: nil,
            isFavorite: false,
            updatedAt: Date(timeIntervalSinceNow: -60)
        )
        let newer = Token(
            id: UUID(),
            name: "Service", issuer: "Corp",
            secret: secret, algorithm: .sha1,
            digits: 6, type: .totp, period: 30, counter: nil,
            isFavorite: true,
            updatedAt: Date()
        )

        try store.update([older, newer])

        XCTAssertEqual(store.tokens.count, 1, "Duplicate content keys must collapse to one token")
        XCTAssertTrue(store.tokens[0].isFavorite,
                      "Newer updatedAt wins — metadata from the most recently modified token is preserved")
    }

    func testExistingTokenAlwaysBeatsNewImportOnContentConflict() throws {
        let existing = makeToken(name: "MyService")
        try store.update([existing])

        var updatedExisting = store.tokens.first!
        updatedExisting.isFavorite = true
        updatedExisting.touch()
        try store.update([updatedExisting])

        let importedNewer = Token(
            id: UUID(),
            name: updatedExisting.name, issuer: updatedExisting.issuer,
            secret: updatedExisting.secret, algorithm: updatedExisting.algorithm,
            digits: updatedExisting.digits, type: updatedExisting.type,
            period: updatedExisting.period, counter: nil,
            isFavorite: false,
            updatedAt: Date(timeIntervalSinceNow: 9999)
        )
        try store.update([updatedExisting, importedNewer])

        XCTAssertEqual(store.tokens.count, 1)
        XCTAssertTrue(store.tokens[0].isFavorite,
                      "Existing in-store token must survive import regardless of the import's updatedAt")
        XCTAssertEqual(store.tokens[0].id, updatedExisting.id,
                       "The surviving token must be the existing one, not the import")
    }

    func testDeleteThenReaddIsNotFavorite() throws {
        let original = makeToken(name: "MyService")
        try store.update([original])

        var updated = store.tokens
        let idx = updated.firstIndex(where: { $0.id == original.id })!
        updated[idx].isFavorite = true
        updated[idx].touch()
        try store.update(updated)
        XCTAssertTrue(store.tokens.first?.isFavorite == true)

        let deleteIdx = store.tokens.firstIndex(where: { $0.id == original.id })!
        try store.delete(at: IndexSet(integer: deleteIdx))
        XCTAssertTrue(store.tokens.isEmpty)

        let readded = makeToken(name: "MyService")
        try store.update([readded])

        XCTAssertEqual(store.tokens.count, 1)
        XCTAssertFalse(store.tokens[0].isFavorite,
                       "Re-added token must not inherit favorite status from the deleted entry")
    }
}
