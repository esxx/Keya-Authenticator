import XCTest

final class NestedSheetsUITests: KeyaUITestCase {
    func testTurningPINOffAsksForPINInPlace() throws {
        try reachMainScreen()
        openSettings(scrollingTo: "App lock")
        button(containing: "App lock").tap()
        if app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 3) {
            enterPIN()
        }
        let pinSwitch = app.switches["PIN"]
        XCTAssertTrue(pinSwitch.waitForExistence(timeout: 5), app.debugDescription)
        pinSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()

        XCTAssertTrue(app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(backButton(to: "App lock").exists, "The PIN is asked inside App lock\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["Cancel"].exists, app.debugDescription)
        backButton(to: "App lock").tap()
        XCTAssertTrue(app.buttons["Change PIN"].waitForExistence(timeout: 5), "Back leaves the PIN on")
    }

    func testRevealSecretAsksForPINInPlace() throws {
        try reachMainScreen()
        addToken(issuer: "Reveal", account: "reveal@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        let row = element(labelContaining: "Reveal")
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.swipeLeft()
        button(containing: "Edit token").tap()

        XCTAssertTrue(app.navigationBars["Edit token"].waitForExistence(timeout: 5), app.debugDescription)
        let reveal = button(containing: "Reveal secret key")
        for _ in 0 ..< 5 where !(reveal.exists && reveal.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(reveal.exists, app.debugDescription)
        reveal.tap()

        XCTAssertTrue(app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(backButton(to: "Edit token").exists, "The PIN is asked inside Edit token\n\(app.debugDescription)")
        enterPIN()

        XCTAssertTrue(button(containing: "Hide secret key").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Edit token"].exists, app.debugDescription)
    }
}
