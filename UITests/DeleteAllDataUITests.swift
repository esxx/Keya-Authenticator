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
}
