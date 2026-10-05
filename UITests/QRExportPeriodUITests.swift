import XCTest

final class QRExportPeriodUITests: KeyaUITestCase {
    func testQRExportNotesTokensWithNon30SecondPeriod() throws {
        try reachMainScreen()
        addToken(issuer: "Standard", account: "std@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")
        addToken(issuer: "Slow", account: "slow@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DQ", period: "60")

        openSettings(scrollingTo: "Export (Backup)")
        button(containing: "Export (Backup)").tap()
        if app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 3) {
            enterPIN()
        }

        let qrExport = button(containing: "Export as QR code")
        XCTAssertTrue(qrExport.waitForExistence(timeout: 5), app.debugDescription)
        qrExport.tap()

        let note = element(labelContaining: "aren't included (1)")
        XCTAssertTrue(note.waitForExistence(timeout: 10),
                      "The 60-second token must be reported as not included\n\(app.debugDescription)")
        XCTAssertTrue(button(containing: "Share QR code").exists, "The 30-second token must still be exported")
    }
}
