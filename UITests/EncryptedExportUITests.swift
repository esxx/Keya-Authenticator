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

        let export = app.buttons.matching(NSPredicate(format: "label == 'Export'")).firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 3), app.debugDescription)
        export.tap()

        let saveDialog = app.buttons["Move"].waitForExistence(timeout: 20) || app.buttons["Save"].exists
        XCTAssertTrue(saveDialog, "Encryption should finish and open the save dialog\n\(app.debugDescription)")
    }
}
