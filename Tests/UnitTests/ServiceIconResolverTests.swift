import SwiftUI
import UIKit
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

    // MARK: - Monogram contrast

    func testEveryBrandMonogramMeetsHIGContrast() {
        var failures: [String] = []
        for (key, info) in ServiceIconResolver.catalog {
            let ratio = Self.contrast(info.foregroundColor, over: info.brandColor)
            if ratio < 4.5 {
                failures.append("\(key) \(String(format: "%.2f", ratio))")
            }
        }
        XCTAssertEqual(failures.sorted(), [], "HIG asks for at least 4.5:1 for text up to 17 pt")
    }

    private static func components(_ color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return (red, green, blue, alpha)
    }

    private static func luminance(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private static func contrast(_ foreground: Color, over background: Color) -> CGFloat {
        let back = components(background)
        let front = components(foreground)
        let mix = { (top: CGFloat, bottom: CGFloat) in top * front.alpha + bottom * (1 - front.alpha) }
        let textLuminance = luminance(
            red: mix(front.red, back.red), green: mix(front.green, back.green), blue: mix(front.blue, back.blue)
        )
        let backLuminance = luminance(red: back.red, green: back.green, blue: back.blue)
        return (max(textLuminance, backLuminance) + 0.05) / (min(textLuminance, backLuminance) + 0.05)
    }
}
