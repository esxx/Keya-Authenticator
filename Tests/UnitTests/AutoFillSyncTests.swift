import AuthenticationServices
import XCTest
@testable import Keya_Authenticator

@MainActor
final class AutoFillSyncTests: XCTestCase {

    final class InMemoryIdentityStore: AutoFillIdentityStore {
        var enabled = true
        private(set) var replacements: [[ASOneTimeCodeCredentialIdentity]] = []

        func isEnabled() async -> Bool {
            enabled
        }

        func replaceIdentities(_ identities: [ASOneTimeCodeCredentialIdentity]) async throws {
            replacements.append(identities)
        }
    }

    private var identityStore: InMemoryIdentityStore!
    private var store: TokenStore!

    override func setUp() {
        super.setUp()
        try? KeychainManager.deleteAllTokens()
        UserDefaults.standard.removeObject(forKey: "tokenSortOrder")
        identityStore = InMemoryIdentityStore()
        store = TokenStore(identityStore: identityStore)
    }

    override func tearDown() {
        try? KeychainManager.deleteAllTokens()
        UserDefaults.standard.removeObject(forKey: "tokenSortOrder")
        store = nil
        identityStore = nil
        super.tearDown()
    }

    private func synced() async {
        await store.autoFillSync?.value
    }

    private func makeToken(
        name: String,
        issuer: String? = nil,
        website: String? = nil,
        type: TokenType = .totp
    ) -> Token {
        var secret = Data(name.utf8)
        while secret.count < 10 { secret.append(0) }
        return Token(name: name, issuer: issuer, secret: secret, type: type,
                     period: type == .totp ? 30 : nil, counter: type == .hotp ? 0 : nil, website: website)
    }

    func testOnlyTOTPTokensWithWebsiteReachAutoFill() async throws {
        let withIssuer = makeToken(name: "a", issuer: "GitHub", website: "github.com")
        let withoutIssuer = makeToken(name: "b", website: "example.com")
        let noWebsite = makeToken(name: "c", issuer: "NoSite")
        let hotp = makeToken(name: "d", issuer: "Counter", website: "counter.com", type: .hotp)

        try store.add([withIssuer, withoutIssuer, noWebsite, hotp])
        await synced()

        let identities = try XCTUnwrap(identityStore.replacements.last)
        let byRecord = Dictionary(uniqueKeysWithValues: identities.map { ($0.recordIdentifier ?? "", $0) })
        XCTAssertEqual(Set(byRecord.keys), [withIssuer.id.uuidString, withoutIssuer.id.uuidString])
        XCTAssertEqual(byRecord[withIssuer.id.uuidString]?.label, "GitHub")
        XCTAssertEqual(byRecord[withIssuer.id.uuidString]?.serviceIdentifier.identifier, "github.com")
        XCTAssertEqual(byRecord[withIssuer.id.uuidString]?.serviceIdentifier.type, .domain)
        XCTAssertEqual(byRecord[withoutIssuer.id.uuidString]?.label, "example.com",
                       "Without an issuer the website is the label, never the account name")
    }

    func testNothingIsWrittenWhileAutoFillIsDisabled() async throws {
        identityStore.enabled = false

        try store.add([makeToken(name: "a", website: "github.com")])
        await synced()

        XCTAssertTrue(identityStore.replacements.isEmpty)
    }

    func testRapidChangesEndWithNewestState() async throws {
        let token = makeToken(name: "a", website: "one.com")
        try store.add([token])

        try store.update(id: token.id) { $0.website = "two.com" }
        try store.update(id: token.id) { $0.website = "three.com" }
        await synced()

        XCTAssertEqual(identityStore.replacements.last?.map(\.serviceIdentifier.identifier), ["three.com"])
    }

    func testLockDoesNotSyncAndDeleteAllSyncsEmptySet() async throws {
        try store.add([makeToken(name: "a", website: "github.com")])
        await synced()
        let countAfterAdd = identityStore.replacements.count

        store.clear()
        await synced()
        XCTAssertEqual(identityStore.replacements.count, countAfterAdd, "Locking must keep AutoFill suggestions")

        try store.deleteAll()
        await synced()
        XCTAssertEqual(identityStore.replacements.last?.count, 0)
    }
}
