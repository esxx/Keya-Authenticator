import XCTest

final class BackupReminderExportUITests: KeyaUITestCase {
    func testExportFromBackupReminderAsksForPIN() throws {
        try reachMainScreen()
        addToken(issuer: "NudgeTest", account: "nudge@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP",
                 dismissBackupNudge: false)

        let reminder = app.alerts["Back up your tokens"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 5), app.debugDescription)
        reminder.buttons["Export"].tap()

        XCTAssertTrue(app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 5),
                      "Export from the reminder must ask for the PIN\n\(app.debugDescription)")
        XCTAssertFalse(app.navigationBars["Export (Backup)"].exists)

        enterPIN()
        let bar = app.navigationBars["Export (Backup)"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "Export should open after the PIN\n\(app.debugDescription)")
        let close = bar.buttons["Close"]
        XCTAssertTrue(close.exists, "Export must have a way to close it\n\(app.debugDescription)")
        close.tap()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 5), app.debugDescription)
    }
}
