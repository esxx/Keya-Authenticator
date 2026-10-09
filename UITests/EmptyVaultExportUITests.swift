import XCTest

final class EmptyVaultExportUITests: KeyaUITestCase {
    func testExportOptionsAreDisabledWithExplanationWhenVaultIsEmpty() throws {
        try reachMainScreen()
        openSettings(scrollingTo: "Export (backup)")
        button(containing: "Export (backup)").tap()
        XCTAssertTrue(app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 5), app.debugDescription)
        enterPIN()

        let json = button(containing: "Export as JSON")
        XCTAssertTrue(json.waitForExistence(timeout: 5), app.debugDescription)
        for label in ["Export as JSON", "Export as encrypted JSON", "Export as QR code"] {
            XCTAssertFalse(button(containing: label).isEnabled, "\(label) should be disabled\n\(app.debugDescription)")
        }
        XCTAssertTrue(app.staticTexts["Add some tokens first before exporting a backup"].exists,
                      "The reason is shown on the screen\n\(app.debugDescription)")

        json.tap()
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2), "No alert\n\(app.debugDescription)")
    }
}
