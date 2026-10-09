import XCTest

final class SettingsNavigationUITests: KeyaUITestCase {
    func testAppLockIsPushedWithPINInPlace() throws {
        try reachMainScreen()
        openSettings(scrollingTo: "App lock")
        button(containing: "App lock").tap()

        XCTAssertTrue(app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(backButton(to: "Settings").exists, "The PIN is asked on the pushed screen\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["Cancel"].exists, app.debugDescription)
        enterPIN()

        XCTAssertTrue(app.buttons["Change PIN"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.navigationBars["App lock"].buttons["Done"].exists, app.debugDescription)
        backButton(to: "Settings").tap()
        XCTAssertTrue(button(containing: "App lock").waitForExistence(timeout: 5), app.debugDescription)
    }

    func testExportIsPushedWithPINInPlace() throws {
        try reachMainScreen()
        openSettings(scrollingTo: "Export (backup)")
        button(containing: "Export (backup)").tap()

        XCTAssertTrue(app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(backButton(to: "Settings").exists, "The PIN is asked on the pushed screen\n\(app.debugDescription)")
        enterPIN()

        XCTAssertTrue(button(containing: "Export as encrypted JSON").waitForExistence(timeout: 5), app.debugDescription)
        backButton(to: "Settings").tap()
        XCTAssertTrue(button(containing: "Export (backup)").waitForExistence(timeout: 5), app.debugDescription)
    }

    func testSupportDevelopmentIsPushed() throws {
        try reachMainScreen()
        openSettings(scrollingTo: "Support development")
        button(containing: "Support development").tap()

        let bar = app.navigationBars["Support development"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(bar.buttons["Done"].exists, app.debugDescription)
        backButton(to: "Settings").tap()
        XCTAssertTrue(button(containing: "Support development").waitForExistence(timeout: 5), app.debugDescription)
    }

    func testManualEntryIsPushedInsideAdd() throws {
        try reachMainScreen()
        app.buttons["Add"].tap()
        dismissSystemAlertIfPresent()

        let manual = button(containing: "Enter the secret key manually")
        XCTAssertTrue(manual.waitForExistence(timeout: 5), app.debugDescription)
        manual.tap()

        XCTAssertTrue(app.navigationBars.buttons["Add"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(backButton(to: "Add tokens").exists, "Manual entry is a step inside Add\n\(app.debugDescription)")
        XCTAssertFalse(app.navigationBars.buttons["Cancel"].exists, app.debugDescription)
        backButton(to: "Add tokens").tap()
        XCTAssertTrue(manual.waitForExistence(timeout: 5), app.debugDescription)
    }
}
