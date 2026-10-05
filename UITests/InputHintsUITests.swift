import XCTest

final class InputHintsUITests: KeyaUITestCase {
    func testPeriodFieldAcceptsTypedValue() throws {
        try reachMainScreen()
        app.buttons["Add"].tap()
        dismissSystemAlertIfPresent()
        let manual = button(containing: "Enter the secret key manually")
        XCTAssertTrue(manual.waitForExistence(timeout: 5), app.debugDescription)
        manual.tap()

        button(containing: "Advanced options").tap()
        let period = app.textFields["30"]
        XCTAssertTrue(period.waitForExistence(timeout: 5), app.debugDescription)
        period.tap()
        period.typeText("60")
        XCTAssertEqual(period.value as? String, "60", "Typing into the period field must not append to a forced 30")
    }

    func testChangePINShowsHintForTooManyDigits() throws {
        try reachMainScreen()
        openSettings(scrollingTo: "App lock")
        button(containing: "App lock").tap()
        if app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 3) {
            enterPIN()
        }

        let changePIN = app.buttons["Change PIN"]
        XCTAssertTrue(changePIN.waitForExistence(timeout: 5), app.debugDescription)
        changePIN.tap()

        let newPIN = app.secureTextFields["New PIN"]
        XCTAssertTrue(newPIN.waitForExistence(timeout: 5), app.debugDescription)
        newPIN.tap()
        newPIN.typeText("1234567")
        XCTAssertTrue(app.staticTexts["PIN must be 6 digits"].waitForExistence(timeout: 3),
                      "A 7-digit PIN must show the length hint\n\(app.debugDescription)")
    }
}
