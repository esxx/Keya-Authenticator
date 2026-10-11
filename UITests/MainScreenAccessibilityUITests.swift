import XCTest

final class MainScreenAccessibilityUITests: KeyaUITestCase {
    func testSettingsButtonIsNamedForVoiceOver() throws {
        try reachMainScreen()

        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5),
                      "The gear button is announced as Settings\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["Gear Shape"].exists, "Not by its symbol name\n\(app.debugDescription)")
    }

    func testNewBadgeIsAtLeastTheMinimumTextSize() throws {
        try reachMainScreen()
        addToken(issuer: "Badge", account: "badge@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        let badge = app.staticTexts["New"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertGreaterThanOrEqual(badge.frame.height, 13, "11 pt text (HIG iOS minimum) needs about 13 pt of height")
    }
}
