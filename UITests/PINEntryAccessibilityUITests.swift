import XCTest

final class PINEntryAccessibilityUITests: KeyaUITestCase {
    private func pinEntry(_ prompt: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ AND value == %@", prompt, "0 of 6 digits entered"))
            .firstMatch
    }

    func testEveryPINScreenTellsVoiceOverWhatToEnter() throws {
        XCTAssertTrue(pinEntry("Create a 6-digit PIN").waitForExistence(timeout: 5),
                      "First run: the PIN entry says what to enter\n\(app.debugDescription)")
        enterPIN()
        XCTAssertTrue(pinEntry("Confirm").waitForExistence(timeout: 5),
                      "Confirm step: the PIN entry says what to enter\n\(app.debugDescription)")
        enterPIN()

        openSettings(scrollingTo: "Export (backup)")
        button(containing: "Export (backup)").tap()
        XCTAssertTrue(pinEntry("Enter PIN to unlock").waitForExistence(timeout: 5),
                      "PIN prompt: the PIN entry says what to enter\n\(app.debugDescription)")
    }
}
