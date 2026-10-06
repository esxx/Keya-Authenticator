import XCTest

final class LockWithOpenSheetUITests: KeyaUITestCase {
    func testQRExportSheetIsNotEmptyAfterLockAndUnlock() throws {
        try reachMainScreen()
        addToken(issuer: "LockTest", account: "lock@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        let row = element(labelContaining: "LockTest")
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.swipeLeft()
        button(containing: "QR code").tap()
        enterPIN()

        let uriLabel = app.staticTexts["otpauth:// URI"]
        XCTAssertTrue(uriLabel.waitForExistence(timeout: 5), "QR export should be open\n\(app.debugDescription)")

        XCUIDevice.shared.press(.home)
        sleep(35)
        app.activate()

        XCTAssertTrue(app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 10),
                      "App should be locked after the grace period\n\(app.debugDescription)")
        enterPIN()
        sleep(2)

        let addButton = app.buttons["Add"]
        let mainScreenUsable = addButton.exists && addButton.isHittable
        XCTAssertTrue(uriLabel.exists || mainScreenUsable,
                      "After unlock the sheet must show its content\n\(app.debugDescription)")
    }
}
