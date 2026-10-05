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

    // MARK: - Token matching

    func testIssuerWordMatches() {
        XCTAssertTrue(BrandKeyword.matches(issuer: "GitHub", name: "me", keyword: "github"))
        XCTAssertTrue(BrandKeyword.matches(issuer: "Amazon Web Services", name: "me", keyword: "amazon"))
    }

    func testShortKeywordDoesNotMatchInsideWords() {
        XCTAssertFalse(BrandKeyword.matches(issuer: "Dropbox", name: "alex@example.com", keyword: "x"))
        XCTAssertFalse(BrandKeyword.matches(issuer: nil, name: "alex@gmail.com", keyword: "x"))
        XCTAssertTrue(BrandKeyword.matches(issuer: "X", name: "me", keyword: "x"))
    }

    func testNameIsIgnoredWhenIssuerIsPresent() {
        XCTAssertFalse(BrandKeyword.matches(issuer: "Google", name: "me@company.com", keyword: "company"))
    }

    func testNameIsUsedWhenIssuerIsMissingOrBlank() {
        XCTAssertTrue(BrandKeyword.matches(issuer: nil, name: "me@github.com", keyword: "github"))
        XCTAssertTrue(BrandKeyword.matches(issuer: "  ", name: "me@github.com", keyword: "github"))
    }
}
