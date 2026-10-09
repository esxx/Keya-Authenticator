import XCTest

final class SheetButtonsUITests: KeyaUITestCase {
    func testSettingsClosesWithClose() throws {
        try reachMainScreen()
        openSettings(scrollingTo: "Delete all data")

        let bar = app.navigationBars["Settings"]
        XCTAssertFalse(bar.buttons["Done"].exists, app.debugDescription)
        let close = bar.buttons["Close"]
        XCTAssertTrue(close.exists, app.debugDescription)
        close.tap()

        XCTAssertTrue(waitForDisappearance(app.staticTexts["Settings"]), app.debugDescription)
    }

    func testAddSheetClosesWithCloseAndManualAddIsInToolbar() throws {
        try reachMainScreen()
        app.buttons["Add"].tap()
        dismissSystemAlertIfPresent()

        let bar = app.navigationBars["Add tokens"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(bar.buttons["Cancel"].exists, app.debugDescription)
        XCTAssertTrue(bar.buttons["Close"].exists, app.debugDescription)

        button(containing: "Enter the secret key manually").tap()
        XCTAssertTrue(app.navigationBars.buttons["Add"].waitForExistence(timeout: 5),
                      "The Add action belongs in the toolbar\n\(app.debugDescription)")
    }

    func testTokenQRExportClosesWithClose() throws {
        try reachMainScreen()
        addToken(issuer: "QRClose", account: "qr@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        let row = element(labelContaining: "QRClose")
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.swipeLeft()
        button(containing: "QR code").tap()
        if app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 3) {
            enterPIN()
        }

        let bar = app.navigationBars["Export"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(bar.buttons["Done"].exists, app.debugDescription)
        let close = bar.buttons["Close"]
        XCTAssertTrue(close.exists, app.debugDescription)
        close.tap()
        XCTAssertTrue(waitForDisappearance(bar), app.debugDescription)
    }

    func testChangePINSheetUsesToolbarButtons() throws {
        try reachMainScreen()
        openSettings(scrollingTo: "App lock")
        button(containing: "App lock").tap()
        if app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 3) {
            enterPIN()
        }

        let change = app.buttons["Change PIN"]
        XCTAssertTrue(change.waitForExistence(timeout: 5), app.debugDescription)
        change.tap()

        let bar = app.navigationBars["Change PIN"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(backButton(to: "App lock").exists, "Change PIN is a step inside App lock\n\(app.debugDescription)")
        XCTAssertFalse(bar.buttons["Cancel"].exists, app.debugDescription)
        XCTAssertTrue(bar.buttons["Save"].exists, app.debugDescription)
        backButton(to: "App lock").tap()
        XCTAssertTrue(change.waitForExistence(timeout: 5), app.debugDescription)
    }
}
