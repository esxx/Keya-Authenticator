import XCTest

final class EncryptedExportUITests: KeyaUITestCase {
    func testEncryptedExportReachesSaveDialog() throws {
        try reachMainScreen()
        addToken(issuer: "EncTest", account: "enc@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        openSettings(scrollingTo: "Export (Backup)")
        button(containing: "Export (Backup)").tap()
        if app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 3) {
            enterPIN()
        }

        let encrypted = button(containing: "Export as encrypted JSON")
        XCTAssertTrue(encrypted.waitForExistence(timeout: 5), app.debugDescription)
        encrypted.tap()

        let password = app.secureTextFields["Password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5), app.debugDescription)
        password.tap()
        password.typeText("testpass1")
        let confirm = app.secureTextFields["Confirm"]
        confirm.tap()
        confirm.typeText("testpass1")

        let bar = app.navigationBars["Export as encrypted JSON"]
        XCTAssertTrue(backButton(to: "Export (Backup)").exists, "The password step is inside Export\n\(app.debugDescription)")
        let export = bar.buttons["Export"]
        XCTAssertTrue(export.waitForExistence(timeout: 3), "Export belongs in the toolbar\n\(app.debugDescription)")
        export.tap()

        let saveDialog = app.buttons["Move"].waitForExistence(timeout: 20) || app.buttons["Save"].exists
        XCTAssertTrue(saveDialog, "Encryption should finish and open the save dialog\n\(app.debugDescription)")
    }
}
