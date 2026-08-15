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

    // MARK: - Content collisions are never auto-merged

    func testUpdateKeepsBothTokensOnIdenticalContent() throws {
        let t = makeToken(name: "Dupe")
        let copy = Token(id: UUID(), name: t.name, issuer: t.issuer,
                         secret: t.secret, algorithm: t.algorithm,
                         digits: t.digits, type: t.type, period: t.period, counter: nil)

        try store.update([t, copy])

        XCTAssertEqual(store.tokens.count, 2,
                       "update() must never silently drop a same-content token; that decision belongs to the caller")
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

    func testUpdateKeepsBothTokensRegardlessOfUpdatedAt() throws {
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

        XCTAssertEqual(store.tokens.count, 2,
                       "update() must not pick a winner by updatedAt; conflict resolution is the caller's job")
    }

    func testUpdateDoesNotDropExistingTokenOnContentConflictWithNewImport() throws {
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

        XCTAssertEqual(store.tokens.count, 2,
                       "The existing token must never be silently deleted by an unrelated update() call")
        XCTAssertTrue(store.tokens.contains { $0.id == updatedExisting.id },
                      "The pre-existing token must still be present")
        XCTAssertTrue(store.tokens.contains { $0.id == importedNewer.id },
                      "The imported token must also be present — both coexist until the user decides")
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

    // MARK: - existingDuplicates(of:)

    func testExistingDuplicatesDetectsContentCollisionWithDifferentID() throws {
        let existing = makeToken(name: "GitHub")
        try store.update([existing])

        let candidate = Token(id: UUID(), name: "GitHub (rescanned)", issuer: existing.issuer,
                              secret: existing.secret, algorithm: existing.algorithm,
                              digits: existing.digits, type: existing.type,
                              period: existing.period, counter: nil)

        let duplicates = store.existingDuplicates(of: [candidate])

        XCTAssertEqual(duplicates.count, 1)
        XCTAssertEqual(duplicates.first?.existing.id, existing.id)
        XCTAssertEqual(duplicates.first?.new.id, candidate.id)
    }

    func testExistingDuplicatesIgnoresSameID() throws {
        let existing = makeToken(name: "GitHub")
        try store.update([existing])

        var edited = existing
        edited.name = "GitHub Renamed"

        let duplicates = store.existingDuplicates(of: [edited])

        XCTAssertTrue(duplicates.isEmpty, "A token cannot be a duplicate of itself")
    }

    func testExistingDuplicatesEmptyWhenNoCollision() throws {
        let existing = makeToken(name: "GitHub")
        try store.update([existing])

        let candidate = makeToken(name: "Discord")

        XCTAssertTrue(store.existingDuplicates(of: [candidate]).isEmpty)
    }

    func testExistingDuplicatesDetectsMultipleCollisionsInBatch() throws {
        let existingA = makeToken(name: "GitHub")
        let existingB = makeToken(name: "Discord")
        try store.update([existingA, existingB])

        let candidateA = Token(id: UUID(), name: "GitHub 2", issuer: existingA.issuer,
                               secret: existingA.secret, algorithm: existingA.algorithm,
                               digits: existingA.digits, type: existingA.type,
                               period: existingA.period, counter: nil)
        let candidateB = Token(id: UUID(), name: "Discord 2", issuer: existingB.issuer,
                               secret: existingB.secret, algorithm: existingB.algorithm,
                               digits: existingB.digits, type: existingB.type,
                               period: existingB.period, counter: nil)
        let newToken = makeToken(name: "Slack")

        let duplicates = store.existingDuplicates(of: [candidateA, candidateB, newToken])

        XCTAssertEqual(duplicates.count, 2)
        XCTAssertTrue(duplicates.contains { $0.new.id == candidateA.id })
        XCTAssertTrue(duplicates.contains { $0.new.id == candidateB.id })
    }

    // MARK: - Keychain-level reads never delete data

    func testLoadAllTokensDoesNotDeleteContentDuplicates() throws {
        let a = Token(id: UUID(), name: "Alpha", issuer: "Corp",
                     secret: secret, algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        let b = Token(id: UUID(), name: "Beta", issuer: "Corp",
                     secret: secret, algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        try KeychainManager.saveToken(a)
        try KeychainManager.saveToken(b)

        let firstLoad = try KeychainManager.loadAllTokens()
        XCTAssertEqual(firstLoad.count, 2, "A plain read must not merge or drop content duplicates")

        let secondLoad = try KeychainManager.loadAllTokens()
        XCTAssertEqual(secondLoad.count, 2,
                       "Reading twice must not have deleted anything from Keychain on the first read")
    }
}
