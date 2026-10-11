import XCTest

final class SettingsPINGateUITests: KeyaUITestCase {
    private func openResetGate() {
        openSettings(scrollingTo: "Delete all data")
        button(containing: "Delete all data").tap()
        XCTAssertTrue(app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "PIN keyboard should appear")
    }

    func testWrongPINKeepsGateClosedAndRightPINOpensIt() throws {
        try reachMainScreen()
        openResetGate()

        app.typeText("1")
        let dots = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ AND value == %@", "Enter PIN to unlock", "1 of 6 digits entered"))
            .firstMatch
        XCTAssertTrue(dots.waitForExistence(timeout: 3), "PIN dots must be announced to VoiceOver\n\(app.debugDescription)")

        app.typeText("23450")
        XCTAssertTrue(element(labelContaining: "Incorrect PIN").waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertFalse(app.alerts["Delete all data?"].exists)

        app.typeText(pin)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "The right PIN leads straight to the confirmation\n\(app.debugDescription)")
        XCTAssertTrue(sheet.buttons["Cancel"].exists, app.debugDescription)
        sheet.buttons["Cancel"].tap()
        XCTAssertTrue(button(containing: "Delete all data").waitForExistence(timeout: 5), "Cancel returns to Settings")
        XCTAssertTrue(app.navigationBars["Settings"].exists, app.debugDescription)
    }

    func testBackLeavesGateWithoutAction() throws {
        try reachMainScreen()
        openResetGate()

        backButton(to: "Settings").tap()

        XCTAssertFalse(app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(app.alerts["Delete all data?"].exists)
        XCTAssertTrue(button(containing: "Delete all data").exists, app.debugDescription)
    }
}
