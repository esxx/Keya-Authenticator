import XCTest
@testable import Keya_Authenticator

final class ServiceIconResolverTests: XCTestCase {

    // MARK: - displayIssuer

    func testDisplayIssuer_plainIssuer_returnsIssuer() {
        XCTAssertEqual(
            ServiceIconResolver.displayIssuer(issuer: "GitHub", name: "user@github.com"),
            "GitHub"
        )
    }

    func testDisplayIssuer_compoundIssuerWithEmbeddedEmail_returnsIssuerAsIs() {
        XCTAssertEqual(
            ServiceIconResolver.displayIssuer(
                issuer: "account.tiger.com (somemail@yahoo.com)",
                name: "somemail@yahoo.com"
            ),
            "account.tiger.com (somemail@yahoo.com)"
        )
    }

    func testDisplayIssuer_bareEmailIssuer_returnsFriendlyName() {
        XCTAssertEqual(
            ServiceIconResolver.displayIssuer(issuer: "user@gmail.com", name: "user@gmail.com"),
            "Gmail"
        )
    }

    func testDisplayIssuer_nilIssuer_nameIsPlainEmail_returnsFriendlyName() {
        XCTAssertEqual(
            ServiceIconResolver.displayIssuer(issuer: nil, name: "alice@yahoo.com"),
            "Yahoo"
        )
    }

    func testDisplayIssuer_nilIssuer_nameIsCompoundWithEmail_returnsNil() {
        XCTAssertNil(
            ServiceIconResolver.displayIssuer(
                issuer: nil,
                name: "account.tiger.com (somemail@yahoo.com)"
            )
        )
    }

    func testDisplayIssuer_emptyIssuer_nameIsCompound_returnsNil() {
        XCTAssertNil(
            ServiceIconResolver.displayIssuer(
                issuer: "",
                name: "account.tiger.com (somemail@yahoo.com)"
            )
        )
    }

    // MARK: - resolve

    func testResolve_compoundNameWithEmbeddedEmail_doesNotMatchEmailDomain() {
        XCTAssertNil(
            ServiceIconResolver.resolve(
                issuer: nil,
                name: "account.tiger.com (somemail@yahoo.com)"
            ),
            "Embedded yahoo.com email must not produce a Yahoo icon"
        )
    }

    func testResolve_explicitIssuerWithEmailAccount_usesIssuerNotEmailDomain() {
        XCTAssertNil(
            ServiceIconResolver.resolve(issuer: "Tiger", name: "user@yahoo.com"),
            "When an explicit issuer is set, the account email domain must never be matched"
        )
    }

    func testResolve_knownIssuer_matchesCatalog() {
        XCTAssertNotNil(
            ServiceIconResolver.resolve(issuer: "GitHub", name: "user@github.com"),
            "Known issuer 'GitHub' should resolve to a catalog entry"
        )
    }

    func testResolve_bareEmailNameNoIssuer_matchesCatalog() {
        XCTAssertNotNil(
            ServiceIconResolver.resolve(issuer: nil, name: "user@github.com"),
            "Plain email from a known domain should resolve via email-domain extraction"
        )
    }

    func testDisplayIssuer_yahooEmail_returnsFriendlyName() {
        XCTAssertEqual(
            ServiceIconResolver.displayIssuer(issuer: nil, name: "alice@yahoo.com"),
            "Yahoo",
            "A plain yahoo.com email should produce 'Yahoo' as the display name"
        )
    }

    func testResolve_yahooEmailWithNoIssuer_returnsNilIcon() {
        XCTAssertNil(
            ServiceIconResolver.resolve(issuer: nil, name: "alice@yahoo.com"),
            "Yahoo has no icon catalog entry — resolve should return nil"
        )
    }

    func testResolve_unknownIssuer_returnsNil() {
        XCTAssertNil(
            ServiceIconResolver.resolve(issuer: "SomeObscureService", name: "user@obscure.example"),
            "Unknown service should return nil"
        )
    }

    func testResolve_shortCatalogKeysDoNotMatchInsideOtherNames() {
        XCTAssertNil(ServiceIconResolver.resolve(issuer: "Foxtrot Bank", name: "me"),
                     "The 'x' key must not give an unrelated issuer the X logo")
        XCTAssertNil(ServiceIconResolver.resolve(issuer: "Real Estate Portal", name: "me"),
                     "The 'ea' key must not give an unrelated issuer the EA logo")
    }

    func testResolve_shortCatalogKeysStillMatchExactly() {
        XCTAssertNotNil(ServiceIconResolver.resolve(issuer: "X", name: "me"))
        XCTAssertNotNil(ServiceIconResolver.resolve(issuer: "EA", name: "me"))
    }

    @MainActor
    func testAvatarPaletteIndexIsStableAcrossLaunches() {
        XCTAssertEqual(TokenRowView.paletteIndex(for: "GitHub", count: 8), 3,
                       "A fixed value proves the index doesn't depend on per-launch hash seeding")
    }
}
