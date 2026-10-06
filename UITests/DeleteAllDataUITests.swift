import XCTest

final class DeleteAllDataUITests: KeyaUITestCase {
    func testDeleteAllDataWipesVaultAndOpensPINSetup() throws {
        try reachMainScreen()

        addToken(issuer: "UITest", account: "user@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")
        XCTAssertTrue(element(labelContaining: "UITest").waitForExistence(timeout: 5),
                      "Added token should be listed\n\(app.debugDescription)")

        openSettings(scrollingTo: "Delete all data")
        button(containing: "Delete all data").tap()

        if app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 3) {
            enterPIN()
        }

        let confirm = app.alerts["Delete all data?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.buttons["Delete"].tap()

        XCTAssertTrue(app.staticTexts["Create a 6-digit PIN"].waitForExistence(timeout: 5),
                      "After a successful reset the app must open PIN setup")
        XCTAssertFalse(button(containing: "Delete all data").exists, "Settings must be closed after reset")
        XCTAssertFalse(app.alerts["Something Went Wrong"].exists)
    }

    func testFailedResetShowsErrorAndKeepsTokens() throws {
        app.terminate()
        app.launchArguments += ["-UITestFailReset"]
        app.launch()
        try reachMainScreen()

        addToken(issuer: "UITestKeep", account: "user@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")
        XCTAssertTrue(element(labelContaining: "UITestKeep").waitForExistence(timeout: 5), app.debugDescription)

        openSettings(scrollingTo: "Delete all data")
        button(containing: "Delete all data").tap()

        if app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 3) {
            enterPIN()
        }

        let confirm = app.alerts["Delete all data?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.buttons["Delete"].tap()

        let failure = app.alerts["Something Went Wrong"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5), "A failed reset must be reported\n\(app.debugDescription)")
        failure.buttons["OK"].tap()

        XCTAssertFalse(app.staticTexts["Create a 6-digit PIN"].exists)
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(element(labelContaining: "UITestKeep").waitForExistence(timeout: 5),
                      "Tokens must stay after a failed reset\n\(app.debugDescription)")
    }
}
