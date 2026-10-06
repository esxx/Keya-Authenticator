import XCTest

final class TokenWebsiteUITests: KeyaUITestCase {
    private func openEdit(issuer: String) {
        let row = element(labelContaining: issuer)
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.swipeLeft()
        button(containing: "Edit token").tap()
        XCTAssertTrue(app.navigationBars["Edit token"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private var websiteField: XCUIElement {
        app.textFields["example.com"]
    }

    func testWebsiteIsSavedNormalizedAndShownOnReopen() throws {
        try reachMainScreen()
        addToken(issuer: "WebsiteTest", account: "site@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        openEdit(issuer: "WebsiteTest")
        XCTAssertTrue(websiteField.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Keya suggests this code in AutoFill on this website."].exists, app.debugDescription)
        websiteField.tap()
        websiteField.typeText("https://GitHub.com/login")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Edit token"].waitForNonExistence(timeout: 5), app.debugDescription)

        openEdit(issuer: "WebsiteTest")
        XCTAssertTrue(websiteField.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(websiteField.value as? String, "github.com")
    }

    func testInvalidWebsiteKeepsEditorOpen() throws {
        try reachMainScreen()
        addToken(issuer: "WebsiteBad", account: "bad@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        openEdit(issuer: "WebsiteBad")
        websiteField.tap()
        websiteField.typeText("not a site")
        app.buttons["Done"].tap()

        let message = element(labelContaining: "Enter a website like example.com")
        for _ in 0 ..< 5 where !message.exists {
            app.swipeUp()
        }
        XCTAssertTrue(message.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Edit token"].exists)
    }
}
