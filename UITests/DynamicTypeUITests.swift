import XCTest

final class DynamicTypeUITests: KeyaUITestCase {
    private func addHOTPToken(issuer: String) {
        app.buttons["Add"].tap()
        dismissSystemAlertIfPresent()
        button(containing: "Enter the secret key manually").tap()

        let issuerField = app.textFields["e.g. AWS, GitHub, Google..."]
        XCTAssertTrue(issuerField.waitForExistence(timeout: 5), app.debugDescription)
        issuerField.tap()
        issuerField.typeText(issuer)
        let accountField = app.textFields["e.g. you@example.com"]
        accountField.tap()
        accountField.typeText("scale@example.com")

        button(containing: "Advanced options").tap()
        let hotp = app.segmentedControls.buttons["HOTP"]
        XCTAssertTrue(hotp.waitForExistence(timeout: 3), app.debugDescription)
        hotp.tap()

        let secretField = app.secureTextFields["Base32 encoded key"]
        secretField.tap()
        secretField.typeText("JBSWY3DPEHPK3PXPJBSWY3DP\n")
        let formAddButton = app.buttons.matching(NSPredicate(format: "label == 'Add' AND identifier != 'plus'")).firstMatch
        XCTAssertTrue(formAddButton.waitForExistence(timeout: 3), app.debugDescription)
        formAddButton.tap()
        let backupNudge = app.alerts["Back up your tokens"]
        if backupNudge.waitForExistence(timeout: 3) {
            backupNudge.buttons["Later"].tap()
        }
    }

    func testIconButtonsGrowWithTheLargestTextSize() throws {
        try reachMainScreen()
        addHOTPToken(issuer: "Scale")

        let row = element(labelContaining: "Scale")
        let refresh = app.buttons["Generate next code"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5), app.debugDescription)
        let defaultRowHeight = row.frame.height
        let defaultRefreshWidth = refresh.frame.width

        app.terminate()
        app.launchArguments = [
            "-UITestIgnoreScreenCapture",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        try reachMainScreen()

        XCTAssertTrue(refresh.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertGreaterThan(row.frame.height, defaultRowHeight,
                             "Control: the largest text size reached the app\n\(app.debugDescription)")
        XCTAssertGreaterThan(refresh.frame.width, defaultRefreshWidth,
                             "The refresh button grows with Dynamic Type\n\(app.debugDescription)")
    }

    func testManualEntryIsReachableAtTheLargestTextSize() throws {
        app.terminate()
        app.launchArguments = [
            "-UITestIgnoreScreenCapture", "-UITestResetState",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        try reachMainScreen()

        app.buttons["Add"].tap()
        dismissSystemAlertIfPresent()
        let manual = button(containing: "Enter the secret key manually")
        XCTAssertTrue(manual.waitForExistence(timeout: 5), app.debugDescription)
        manual.tap()
        XCTAssertTrue(app.textFields["e.g. AWS, GitHub, Google..."].waitForExistence(timeout: 5),
                      "Every way to add a token stays reachable with the largest text\n\(app.debugDescription)")
    }
}
