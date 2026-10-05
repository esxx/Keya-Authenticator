import XCTest

@MainActor
final class DeleteAllDataUITests: XCTestCase {
    private let pin = "123456"
    private let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launchArguments = ["-UITestIgnoreScreenCapture"]
        app.launch()
    }

    func testDeleteAllDataWipesVaultAndOpensPINSetup() throws {
        try reachMainScreen()

        addToken(issuer: "UITest", account: "user@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")
        let tokenRow = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'UITest'")).firstMatch
        XCTAssertTrue(tokenRow.waitForExistence(timeout: 5), "Added token should be listed\n\(app.debugDescription)")

        openSettings()
        button(containing: "Delete all data").tap()

        if app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 3) {
            enterPIN()
        }

        let confirm = app.alerts["Delete all data?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.buttons["Delete"].tap()

        XCTAssertTrue(app.staticTexts["Create a 6-digit PIN"].waitForExistence(timeout: 5),
                      "After a successful reset the app must open PIN setup")
        XCTAssertFalse(button(containing: "Delete all data").exists, "Settings must be closed after reset")
        XCTAssertFalse(app.alerts["Something Went Wrong"].exists)
    }

    // MARK: - Steps

    private func reachMainScreen() throws {
        if app.staticTexts["Create a 6-digit PIN"].waitForExistence(timeout: 5) {
            enterPIN()
            XCTAssertTrue(app.staticTexts["Confirm"].waitForExistence(timeout: 3))
            enterPIN()
        } else if app.staticTexts["Enter PIN to unlock"].exists {
            enterPIN()
        }
        guard app.buttons["Add"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Could not reach the token list; the app may be locked with a PIN other than the test PIN")
        }
    }

    private func addToken(issuer: String, account: String, secret: String) {
        app.buttons["Add"].tap()
        dismissSystemAlertIfPresent()

        let manual = button(containing: "Enter the secret key manually")
        XCTAssertTrue(manual.waitForExistence(timeout: 5), app.debugDescription)
        manual.tap()

        let issuerField = app.textFields["e.g. AWS, GitHub, Google..."]
        XCTAssertTrue(issuerField.waitForExistence(timeout: 5))
        issuerField.tap()
        issuerField.typeText(issuer)

        let accountField = app.textFields["e.g. you@example.com"]
        accountField.tap()
        accountField.typeText(account)

        let secretField = app.secureTextFields["Base32 encoded key"]
        secretField.tap()
        secretField.typeText(secret + "\n")

        let formAddButton = app.buttons.matching(NSPredicate(format: "label == 'Add' AND identifier != 'plus'")).firstMatch
        XCTAssertTrue(formAddButton.waitForExistence(timeout: 3), app.debugDescription)
        formAddButton.tap()

        let duplicate = app.alerts["Duplicate token"]
        if duplicate.waitForExistence(timeout: 2) {
            duplicate.buttons["Add Anyway"].tap()
        }

        let backupNudge = app.alerts["Back up your tokens"]
        if backupNudge.waitForExistence(timeout: 3) {
            backupNudge.buttons["Later"].tap()
        }
    }

    private func openSettings() {
        let candidates = ["Settings", "gearshape"]
        for label in candidates where app.buttons[label].exists {
            app.buttons[label].tap()
            break
        }
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5), app.debugDescription)
        let deleteButton = button(containing: "Delete all data")
        for _ in 0 ..< 5 where !(deleteButton.exists && deleteButton.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(deleteButton.exists && deleteButton.isHittable, app.debugDescription)
    }

    private func button(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func enterPIN() {
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "PIN keyboard should appear")
        app.typeText(pin)
    }

    private func dismissSystemAlertIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 2) {
            alert.buttons.allElementsBoundByIndex.last?.tap()
        }
    }
}
