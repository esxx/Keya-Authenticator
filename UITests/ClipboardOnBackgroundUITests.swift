import XCTest

final class ClipboardOnBackgroundUITests: KeyaUITestCase {
    func testCopiedCodeSurvivesSwitchingApps() throws {
        try reachMainScreen()
        addToken(issuer: "ClipTest", account: "clip@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        let row = element(labelContaining: "ClipTest")
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.tap()
        XCTAssertTrue(app.staticTexts["Copied"].waitForExistence(timeout: 3), "Tapping a token should copy its code")

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()

        let add = app.buttons["Add"]
        waitUntilSettled(add)
        add.tap()
        dismissSystemAlertIfPresent()
        let manual = button(containing: "Enter the secret key manually")
        XCTAssertTrue(manual.waitForExistence(timeout: 5), app.debugDescription)
        manual.tap()
        let field = app.textFields["e.g. AWS, GitHub, Google..."]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.press(forDuration: 1.2)
        let paste = app.menuItems["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 3),
                      "The copied code should still be pasteable after switching apps\n\(app.debugDescription)")
    }
}
