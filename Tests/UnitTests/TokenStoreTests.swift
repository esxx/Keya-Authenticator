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
        store.load()
        XCTAssertEqual(store.tokens.map(\.name), savedOrder,
                       "Sort order should be preserved across a fresh load")
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
        store.delete(at: IndexSet(integer: removeIndex))

        XCTAssertEqual(store.tokens.count, 1)
        XCTAssertEqual(store.tokens.first?.name, "Keep")
    }

    func testDeleteAllEmptiesStore() throws {
        try store.update([makeToken(name: "A"), makeToken(name: "B")])
        store.deleteAll()
        XCTAssertTrue(store.tokens.isEmpty)
    }

    // MARK: - Clear (security wipe)

    func testClearZeroesSecretsAndEmptiesStore() throws {
        try store.update([makeToken(name: "Sensitive")])
        store.clear()
        XCTAssertTrue(store.tokens.isEmpty)
    }

    // MARK: - isFavorite dedup regression

    func testDedupConflictStripsIsFavorite() throws {
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
        XCTAssertFalse(store.tokens[0].isFavorite,
                       "isFavorite must be stripped when dedup resolves a conflict")
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
        store.delete(at: IndexSet(integer: deleteIdx))
        XCTAssertTrue(store.tokens.isEmpty)

        let readded = makeToken(name: "MyService")
        try store.update([readded])

        XCTAssertEqual(store.tokens.count, 1)
        XCTAssertFalse(store.tokens[0].isFavorite,
                       "Re-added token must not inherit favorite status from the deleted entry")
    }
}
