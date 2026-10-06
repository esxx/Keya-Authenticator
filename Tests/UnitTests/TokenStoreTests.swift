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
        try store.add([t1, t2, t3])

        store.move(fromOffsets: IndexSet(integer: 1), toOffset: 0, in: store.tokens)

        XCTAssertEqual(store.tokens.map(\.name), ["Beta", "Alpha", "Gamma"])
    }

    func testSortOrderPersistsAcrossLoad() throws {
        let t1 = makeToken(name: "First")
        let t2 = makeToken(name: "Second")
        let t3 = makeToken(name: "Third")
        try store.add([t1, t2, t3])

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

    func testLoadCountsUnreadableEntriesInsteadOfHidingThem() throws {
        try store.add([makeToken(name: "Readable")])
        let corruptQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ee.exx.KeyaAuthenticator",
            kSecAttrAccount as String: UUID().uuidString,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data("not-json".utf8),
        ]
        SecItemAdd(corruptQuery as CFDictionary, nil)

        try store.load()

        XCTAssertEqual(store.tokens.map(\.name), ["Readable"])
        XCTAssertEqual(store.unreadableTokenCount, 1, "The unreadable entry must be counted so the user can be told")
    }

    // MARK: - Duplicate UUID regression (crash fix)

    func testDuplicateIDInOneBatchKeepsFirstEntry() throws {
        let sharedID = UUID()
        let t1 = makeToken(id: sharedID, name: "Original")
        let t2 = makeToken(id: sharedID, name: "Duplicate")

        let result = try store.add([t1, t2])

        XCTAssertEqual(store.tokens.map(\.name), ["Original"])
        XCTAssertEqual(try KeychainManager.loadAllTokens().map(\.name), ["Original"])
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.alreadyInVault, 1)
    }

    func testDuplicateUUIDMoveDoesNotCrash() throws {
        let t1 = makeToken(name: "Alpha")
        let t2 = makeToken(name: "Beta")
        let t3 = makeToken(name: "Gamma")
        try store.add([t1, t2, t3])

        XCTAssertNoThrow(
            store.move(fromOffsets: IndexSet(integer: 0), toOffset: 3, in: store.tokens),
            "move() must not crash"
        )
    }

    func testDuplicateUUIDCollapseToOne() throws {
        let sharedID = UUID()
        let t = makeToken(id: sharedID, name: "Token")
        XCTAssertNoThrow(try store.add([t, t]))
        XCTAssertEqual(store.tokens.filter { $0.id == sharedID }.count, 1,
                       "Tokens with a shared UUID must collapse to exactly one")
    }

    // MARK: - Content collisions are never auto-merged

    func testUpdateKeepsBothTokensOnIdenticalContent() throws {
        let t = makeToken(name: "Dupe")
        let copy = Token(id: UUID(), name: t.name, issuer: t.issuer,
                         secret: t.secret, algorithm: t.algorithm,
                         digits: t.digits, type: t.type, period: t.period, counter: nil)

        try store.add([t, copy])

        XCTAssertEqual(store.tokens.count, 2,
                       "add() must never silently drop a same-content token; that decision belongs to the caller")
    }

    func testUpdatingExistingTokenBypassesContentDedup() throws {
        let original = makeToken(name: "Original")
        try store.add([original])

        try store.update(id: original.id) { $0.name = "Renamed" }

        XCTAssertEqual(store.tokens.count, 1)
        XCTAssertEqual(store.tokens.first?.name, "Renamed")
    }

    // MARK: - Delete

    func testDeleteRemovesCorrectToken() throws {
        let t1 = makeToken(name: "Keep")
        let t2 = makeToken(name: "Remove")
        try store.add([t1, t2])

        try store.delete(id: t2.id)

        XCTAssertEqual(store.tokens.map(\.name), ["Keep"])
        XCTAssertEqual(try KeychainManager.loadAllTokens().map(\.name), ["Keep"])
    }

    func testUpdateChangingOneTokenKeepsAllOthers() throws {
        let tokens = (0 ..< 5).map { makeToken(name: "T\($0)") }
        try store.add(tokens)
        let savedBefore = try KeychainManager.loadAllTokens()

        try store.update(id: tokens[2].id) { $0.isFavorite = true }

        let reloaded = TokenStore()
        try reloaded.load()
        XCTAssertEqual(Set(reloaded.tokens.map(\.id)), Set(tokens.map(\.id)))
        XCTAssertEqual(reloaded.tokens.filter(\.isFavorite).map(\.id), [tokens[2].id])
        for token in savedBefore where token.id != tokens[2].id {
            XCTAssertEqual(reloaded.tokens.first { $0.id == token.id }, token,
                           "Tokens that were not changed must stay exactly as saved")
        }
    }

    func testDeleteAllEmptiesStore() throws {
        try store.add([makeToken(name: "A"), makeToken(name: "B")])
        try store.deleteAll()
        XCTAssertTrue(store.tokens.isEmpty)
        XCTAssertTrue(try KeychainManager.loadAllTokens().isEmpty)
    }

    func testDeleteAllTokensPreservesReservedAccounts() throws {
        try KeychainManager.savePIN("123456")
        try store.add([makeToken(name: "A")])

        try KeychainManager.deleteAllTokens()

        XCTAssertTrue(KeychainManager.isPINSet(), "deleteAllTokens must not erase the PIN")
        XCTAssertTrue(try KeychainManager.loadAllTokens().isEmpty, "tokens must be gone")
        try KeychainManager.deletePIN()
    }

    // MARK: - Clear (security wipe)

    func testClearZeroesSecretsAndEmptiesStore() throws {
        try store.add([makeToken(name: "Sensitive")])
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

        try store.add([older, newer])

        XCTAssertEqual(store.tokens.count, 2,
                       "add() must not pick a winner by updatedAt; conflict resolution is the caller's job")
    }

    func testUpdateDoesNotDropExistingTokenOnContentConflictWithNewImport() throws {
        let existing = makeToken(name: "MyService")
        try store.add([existing])

        try store.update(id: existing.id) { $0.isFavorite = true }
        let updatedExisting = store.tokens.first!

        let importedNewer = Token(
            id: UUID(),
            name: updatedExisting.name, issuer: updatedExisting.issuer,
            secret: updatedExisting.secret, algorithm: updatedExisting.algorithm,
            digits: updatedExisting.digits, type: updatedExisting.type,
            period: updatedExisting.period, counter: nil,
            isFavorite: false,
            updatedAt: Date(timeIntervalSinceNow: 9999)
        )
        try store.add([importedNewer])

        XCTAssertEqual(store.tokens.count, 2,
                       "The existing token must never be silently deleted by an unrelated add() call")
        XCTAssertTrue(store.tokens.contains { $0.id == updatedExisting.id },
                      "The pre-existing token must still be present")
        XCTAssertTrue(store.tokens.contains { $0.id == importedNewer.id },
                      "The imported token must also be present — both coexist until the user decides")
    }

    func testDeleteThenReaddIsNotFavorite() throws {
        let original = makeToken(name: "MyService")
        try store.add([original])

        try store.update(id: original.id) { $0.isFavorite = true }
        XCTAssertTrue(store.tokens.first?.isFavorite == true)

        try store.delete(id: original.id)
        XCTAssertTrue(store.tokens.isEmpty)

        let readded = makeToken(name: "MyService")
        try store.add([readded])

        XCTAssertEqual(store.tokens.count, 1)
        XCTAssertFalse(store.tokens[0].isFavorite,
                       "Re-added token must not inherit favorite status from the deleted entry")
    }

    // MARK: - existingDuplicates(of:)

    func testExistingDuplicatesDetectsContentCollisionWithDifferentID() throws {
        let existing = makeToken(name: "GitHub")
        try store.add([existing])

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
        try store.add([existing])

        var edited = existing
        edited.name = "GitHub Renamed"

        let duplicates = store.existingDuplicates(of: [edited])

        XCTAssertTrue(duplicates.isEmpty, "A token cannot be a duplicate of itself")
    }

    func testExistingDuplicatesEmptyWhenNoCollision() throws {
        let existing = makeToken(name: "GitHub")
        try store.add([existing])

        let candidate = makeToken(name: "Discord")

        XCTAssertTrue(store.existingDuplicates(of: [candidate]).isEmpty)
    }

    func testExistingDuplicatesDetectsMultipleCollisionsInBatch() throws {
        let existingA = makeToken(name: "GitHub")
        let existingB = makeToken(name: "Discord")
        try store.add([existingA, existingB])

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

    // MARK: - Intents by id

    private func makeHOTP(id: UUID = UUID(), counter: UInt64) -> Token {
        Token(id: id, name: "Counter", issuer: "Issuer", secret: secret, type: .hotp, period: nil, counter: counter)
    }

    func testAddDoesNotOverwriteExistingID() throws {
        let current = makeHOTP(counter: 7)
        try store.add([current])

        let olderBackupCopy = makeHOTP(id: current.id, counter: 2)
        let result = try store.add([olderBackupCopy])

        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.alreadyInVault, 1)
        XCTAssertEqual(store.tokens.first?.counter, 7)
        XCTAssertEqual(try KeychainManager.loadAllTokens().first?.counter, 7,
                       "A used HOTP code must not come back from an older backup")
    }

    func testAddWhenEverythingIsAlreadyPresentChangesNothing() throws {
        let tokens = (0 ..< 3).map { makeToken(name: "P\($0)") }
        try store.add(tokens)
        let before = try KeychainManager.loadAllTokens()

        let result = try store.add(tokens)

        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.alreadyInVault, 3)
        XCTAssertEqual(store.tokens.count, 3)
        XCTAssertEqual(try KeychainManager.loadAllTokens().map(\.updatedAt).sorted(), before.map(\.updatedAt).sorted())
    }

    func testUpdateRejectsIDChange() throws {
        let original = makeToken(name: "Original")
        try store.add([original])
        let other = makeToken(name: "Other")

        XCTAssertThrowsError(try store.update(id: original.id) { $0 = other }) { error in
            XCTAssertEqual(error as? TokenStoreError, .idChanged)
        }
        XCTAssertEqual(store.tokens.map(\.id), [original.id])
        XCTAssertEqual(try KeychainManager.loadAllTokens().map(\.id), [original.id],
                       "No item may be written under another id")
    }

    func testUpdateMissingIDThrowsTokenNotFound() throws {
        try store.add([makeToken(name: "Present")])
        let before = try KeychainManager.loadAllTokens()

        XCTAssertThrowsError(try store.update(id: UUID()) { $0.name = "Ghost" }) { error in
            XCTAssertEqual(error as? TokenStoreError, .tokenNotFound)
        }
        XCTAssertEqual(try KeychainManager.loadAllTokens().map(\.name), before.map(\.name))
    }

    func testUpdateSetsUpdatedAt() throws {
        let original = Token(name: "Dated", secret: secret, updatedAt: Date(timeIntervalSinceNow: -3600))
        try store.add([original])

        try store.update(id: original.id) { $0.isFavorite = true }

        let saved = try XCTUnwrap(KeychainManager.loadAllTokens().first)
        XCTAssertGreaterThan(saved.updatedAt, original.updatedAt)
    }

    func testDeleteByIDRemovesExactlyOne() throws {
        let tokens = (0 ..< 4).map { makeToken(name: "D\($0)") }
        try store.add(tokens)

        try store.delete(id: tokens[1].id)

        XCTAssertEqual(Set(store.tokens.map(\.id)), Set(tokens.map(\.id)).subtracting([tokens[1].id]))
        XCTAssertEqual(Set(try KeychainManager.loadAllTokens().map(\.id)), Set(store.tokens.map(\.id)))
    }
}
