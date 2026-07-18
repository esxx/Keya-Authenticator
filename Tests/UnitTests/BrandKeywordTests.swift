import XCTest
@testable import Keya_Authenticator

final class BrandKeywordTests: XCTestCase {

    func testSimpleDomain() {
        XCTAssertEqual(BrandKeyword.extract(fromHost: "github.com"), "github")
    }

    func testSubdomainIsIgnored() {
        XCTAssertEqual(BrandKeyword.extract(fromHost: "accounts.google.com"), "google")
    }

    func testWwwIsStripped() {
        XCTAssertEqual(BrandKeyword.extract(fromHost: "www.github.com"), "github")
    }

    func testTwoLevelTLD() {
        XCTAssertEqual(BrandKeyword.extract(fromHost: "amazon.co.uk"), "amazon")
    }

    func testSubdomainWithTwoLevelTLD() {
        XCTAssertEqual(BrandKeyword.extract(fromHost: "accounts.google.co.uk"), "google")
    }

    func testAcademicTLD() {
        XCTAssertEqual(BrandKeyword.extract(fromHost: "portal.ox.ac.uk"), "ox")
    }

    func testBareTwoLabelHostWithRegistryLabel() {
        XCTAssertEqual(BrandKeyword.extract(fromHost: "gov.uk"), "gov")
    }

    func testSingleLabelHost() {
        XCTAssertEqual(BrandKeyword.extract(fromHost: "localhost"), "localhost")
    }

    func testUppercaseHostIsLowercased() {
        XCTAssertEqual(BrandKeyword.extract(fromHost: "Accounts.GitHub.COM"), "github")
    }
}
