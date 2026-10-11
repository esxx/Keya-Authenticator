import XCTest

final class MainScreenAccessibilityUITests: KeyaUITestCase {
    func testSettingsButtonIsNamedForVoiceOver() throws {
        try reachMainScreen()

        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5),
                      "The gear button is announced as Settings\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["Gear Shape"].exists, "Not by its symbol name\n\(app.debugDescription)")
    }
}
