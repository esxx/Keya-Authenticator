import XCTest

final class DeleteTokenPINUITests: KeyaUITestCase {
    func testCancellingThePINKeepsTheToken() throws {
        try reachMainScreen()
        addToken(issuer: "KeepMe", account: "keep@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        let row = app.staticTexts["KeepMe"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.swipeLeft()
        button(containing: "Delete").tap()

        XCTAssertTrue(app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(waitForDisappearance(app.staticTexts["Enter PIN to unlock"]), app.debugDescription)
        XCTAssertFalse(app.sheets.firstMatch.waitForExistence(timeout: 2),
                       "Cancelling the PIN shows no delete confirmation\n\(app.debugDescription)")
        XCTAssertTrue(row.exists, "Cancelling the PIN keeps the token\n\(app.debugDescription)")
    }

    func testWithAppLockOffDeleteGoesStraightToConfirmation() throws {
        try reachMainScreen()
        addToken(issuer: "NoLock", account: "nolock@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        openSettings(scrollingTo: "App lock")
        button(containing: "App lock").tap()
        if app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 3) {
            enterPIN()
        }
        let pinSwitch = app.switches["PIN"]
        XCTAssertTrue(pinSwitch.waitForExistence(timeout: 5), app.debugDescription)
        pinSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(pinSwitch.value as? String, "0", "App lock is off\n\(app.debugDescription)")
        backButton(to: "Settings").tap()
        app.buttons["Close"].tap()

        let row = app.staticTexts["NoLock"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.swipeLeft()
        button(containing: "Delete").tap()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5),
                      "With App lock off the confirmation comes at once\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["Enter PIN to unlock"].exists, app.debugDescription)
        app.sheets.buttons["Delete"].tap()
        XCTAssertTrue(waitForDisappearance(row), app.debugDescription)
    }
}
