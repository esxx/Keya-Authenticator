import XCTest

final class ContextMenuUITests: KeyaUITestCase {
    func testLongPressOffersTheSameActionsAsSwipes() throws {
        try reachMainScreen()
        addToken(issuer: "MenuTest", account: "menu@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        let row = app.staticTexts["MenuTest"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.press(forDuration: 1.2)

        for label in ["Copy", "Favorite", "Edit token", "QR code", "Delete"] {
            XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 3),
                          "The context menu offers \(label)\n\(app.debugDescription)")
        }
        app.buttons["Edit token"].tap()
        XCTAssertTrue(app.navigationBars["Edit token"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testDeleteFromMenuAsksForPINAndCancelKeepsTheRow() throws {
        try reachMainScreen()
        addToken(issuer: "MenuDelete", account: "menu@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        let row = app.staticTexts["MenuDelete"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3), app.debugDescription)
        app.buttons["Delete"].tap()

        XCTAssertTrue(app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(waitForDisappearance(app.staticTexts["Enter PIN to unlock"]), app.debugDescription)
        XCTAssertTrue(row.waitForExistence(timeout: 3), "Cancelling the PIN keeps the row\n\(app.debugDescription)")
    }
}
