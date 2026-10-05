import XCTest

final class SecretShareUITests: KeyaUITestCase {
    private func openQRExport() throws {
        try reachMainScreen()
        addToken(issuer: "ShareTest", account: "share@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")
        let row = element(labelContaining: "ShareTest")
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.swipeLeft()
        button(containing: "QR code").tap()
        enterPIN()
        XCTAssertTrue(app.staticTexts["otpauth:// URI"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testSharingQRCodeAsksForConfirmationFirst() throws {
        try openQRExport()

        button(containing: "Share QR code").tap()
        let warning = app.alerts["Unencrypted export"]
        XCTAssertTrue(warning.waitForExistence(timeout: 3), "Sharing secrets must be confirmed\n\(app.debugDescription)")
        warning.buttons["Cancel"].tap()
        XCTAssertFalse(warning.waitForExistence(timeout: 1))

        button(containing: "Share QR code").tap()
        XCTAssertTrue(warning.waitForExistence(timeout: 3))
        warning.buttons["Export"].tap()
        let shareSheet = app.otherElements["ActivityListView"].exists
            ? app.otherElements["ActivityListView"]
            : app.otherElements.matching(identifier: "ActivityListView").firstMatch
        let opened = shareSheet.waitForExistence(timeout: 5)
            || app.navigationBars["UIActivityContentView"].waitForExistence(timeout: 2)
        XCTAssertTrue(opened, "The share sheet should open after confirming\n\(app.debugDescription)")
    }

    func testCopyButtonCopiesLink() throws {
        try openQRExport()
        let copy = button(containing: "Copy")
        XCTAssertTrue(copy.waitForExistence(timeout: 3), app.debugDescription)
        copy.tap()
        XCTAssertTrue(button(containing: "Copied").waitForExistence(timeout: 2), app.debugDescription)
    }
}
