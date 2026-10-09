import XCTest

final class ManualEntryUITests: KeyaUITestCase {
    func testAdvancedOptionsUseSegmentedControls() throws {
        try reachMainScreen()
        app.buttons["Add"].tap()
        dismissSystemAlertIfPresent()
        button(containing: "Enter the secret key manually").tap()

        let advanced = button(containing: "Advanced options")
        XCTAssertTrue(advanced.waitForExistence(timeout: 5), app.debugDescription)
        advanced.tap()

        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(app.segmentedControls.count, 3, "Type, algorithm and digits\n\(app.debugDescription)")
        XCTAssertTrue(app.segmentedControls.buttons["SHA-256"].exists, app.debugDescription)

        app.segmentedControls.buttons["HOTP"].tap()
        XCTAssertTrue(app.textFields["0"].waitForExistence(timeout: 3), "HOTP asks for the initial counter")
    }

    func testEditShowsTheSameAlgorithmNames() throws {
        try reachMainScreen()
        addToken(issuer: "Algo", account: "algo@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        let row = element(labelContaining: "Algo")
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.swipeLeft()
        button(containing: "Edit token").tap()

        XCTAssertTrue(app.navigationBars["Edit token"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element(labelContaining: "SHA-1").waitForExistence(timeout: 3), app.debugDescription)
    }
}
