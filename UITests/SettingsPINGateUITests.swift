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
        let dots = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "PIN entry dots")).firstMatch
        XCTAssertTrue(dots.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(dots.value as? String, "1 of 6 digits entered", "PIN dots must be announced to VoiceOver")

        app.typeText("23450")
        XCTAssertTrue(element(labelContaining: "Incorrect PIN").waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertFalse(app.alerts["Delete all data?"].exists)

        app.typeText(pin)
        let confirm = app.alerts["Delete all data?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.buttons["Cancel"].tap()
        XCTAssertTrue(button(containing: "Delete all data").waitForExistence(timeout: 3), app.debugDescription)
    }

    func testCancelClosesGateWithoutAction() throws {
        try reachMainScreen()
        openResetGate()

        app.buttons["Cancel"].firstMatch.tap()

        XCTAssertFalse(app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(app.alerts["Delete all data?"].exists)
        XCTAssertTrue(button(containing: "Delete all data").exists, app.debugDescription)
    }
}
