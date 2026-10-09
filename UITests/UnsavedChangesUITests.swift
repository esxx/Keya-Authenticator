import XCTest

final class UnsavedChangesUITests: KeyaUITestCase {
    private func openEdit(_ issuer: String) -> XCUIElement {
        let row = element(labelContaining: issuer)
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.swipeLeft()
        button(containing: "Edit token").tap()
        let bar = app.navigationBars["Edit token"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), app.debugDescription)
        return bar
    }

    private func changeWebsite() {
        let website = app.textFields["example.com"]
        XCTAssertTrue(website.waitForExistence(timeout: 3), app.debugDescription)
        website.tap()
        website.typeText("x.com\n")
    }

    private func dragSheetDown(from bar: XCUIElement) {
        let top = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
    }

    private func assertDiscardActionSheet() {
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3), "Unsaved changes are confirmed with an action sheet\n\(app.debugDescription)")
        XCTAssertTrue(sheet.buttons["Discard changes"].exists, app.debugDescription)
        XCTAssertTrue(sheet.buttons["Cancel"].exists, "The action sheet has a visible Cancel\n\(app.debugDescription)")
    }

    func testEditCancelWithoutChangesClosesAtOnce() throws {
        try reachMainScreen()
        addToken(issuer: "EditPlain", account: "plain@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        let bar = openEdit("EditPlain")
        bar.buttons["Cancel"].tap()
        XCTAssertTrue(waitForDisappearance(bar), app.debugDescription)
    }

    func testEditCancelWithChangesClosesWithoutAsking() throws {
        try reachMainScreen()
        addToken(issuer: "EditCancel", account: "cancel@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        var bar = openEdit("EditCancel")
        changeWebsite()
        bar.buttons["Cancel"].tap()
        XCTAssertTrue(waitForDisappearance(bar), "Cancel closes at once\n\(app.debugDescription)")
        XCTAssertFalse(app.sheets.firstMatch.exists, app.debugDescription)

        bar = openEdit("EditCancel")
        XCTAssertTrue(app.textFields["example.com"].waitForExistence(timeout: 3),
                      "Cancel must not save the change\n\(app.debugDescription)")
    }

    func testEditSwipeWithChangesAsksWithActionSheet() throws {
        try reachMainScreen()
        addToken(issuer: "EditSwipe", account: "swipe@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        let bar = openEdit("EditSwipe")
        changeWebsite()
        dragSheetDown(from: bar)
        assertDiscardActionSheet()
        app.sheets.buttons["Cancel"].tap()
        XCTAssertTrue(bar.exists, app.debugDescription)
    }

    func testAddSwipeWithInputAsksWithActionSheet() throws {
        try reachMainScreen()
        app.buttons["Add"].tap()
        dismissSystemAlertIfPresent()

        button(containing: "Enter the secret key manually").tap()
        let issuerField = app.textFields["e.g. AWS, GitHub, Google..."]
        XCTAssertTrue(issuerField.waitForExistence(timeout: 5), app.debugDescription)
        issuerField.tap()
        issuerField.typeText("Draft\n")
        backButton(to: "Add tokens").tap()

        let bar = app.navigationBars["Add tokens"]
        dragSheetDown(from: bar)
        assertDiscardActionSheet()
        app.sheets.buttons["Cancel"].tap()
        XCTAssertTrue(bar.exists, "Cancel in the action sheet keeps the input\n\(app.debugDescription)")

        dragSheetDown(from: bar)
        assertDiscardActionSheet()
        app.sheets.buttons["Discard changes"].tap()
        XCTAssertTrue(waitForDisappearance(bar), app.debugDescription)
    }

    func testAddCloseWithInputClosesWithoutAsking() throws {
        try reachMainScreen()
        app.buttons["Add"].tap()
        dismissSystemAlertIfPresent()

        button(containing: "Enter the secret key manually").tap()
        let issuerField = app.textFields["e.g. AWS, GitHub, Google..."]
        XCTAssertTrue(issuerField.waitForExistence(timeout: 5), app.debugDescription)
        issuerField.tap()
        issuerField.typeText("Draft\n")
        backButton(to: "Add tokens").tap()

        let bar = app.navigationBars["Add tokens"]
        bar.buttons["Close"].tap()
        XCTAssertTrue(waitForDisappearance(bar), "Close closes at once\n\(app.debugDescription)")
        XCTAssertFalse(app.sheets.firstMatch.exists, app.debugDescription)
    }

    func testAddCloseDiscardsTypedInput() throws {
        try reachMainScreen()
        app.buttons["Add"].tap()
        dismissSystemAlertIfPresent()

        button(containing: "Enter the secret key manually").tap()
        let issuerField = app.textFields["e.g. AWS, GitHub, Google..."]
        XCTAssertTrue(issuerField.waitForExistence(timeout: 5), app.debugDescription)
        issuerField.tap()
        issuerField.typeText("Draft\n")
        dragSheetDown(from: app.navigationBars.firstMatch)
        if app.sheets.firstMatch.waitForExistence(timeout: 2) {
            app.sheets.buttons["Cancel"].tap()
        }
        backButton(to: "Add tokens").tap()
        app.navigationBars["Add tokens"].buttons["Close"].tap()
        XCTAssertTrue(waitForDisappearance(app.navigationBars["Add tokens"]), app.debugDescription)

        app.buttons["Add"].tap()
        button(containing: "Enter the secret key manually").tap()
        let reopened = app.textFields["e.g. AWS, GitHub, Google..."]
        XCTAssertTrue(reopened.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertNotEqual(reopened.value as? String, "Draft", "Closing discards what was typed\n\(app.debugDescription)")
    }

    func testAddSwipeOnManualEntryWithInputAsks() throws {
        try reachMainScreen()
        app.buttons["Add"].tap()
        dismissSystemAlertIfPresent()

        button(containing: "Enter the secret key manually").tap()
        let issuerField = app.textFields["e.g. AWS, GitHub, Google..."]
        XCTAssertTrue(issuerField.waitForExistence(timeout: 5), app.debugDescription)
        issuerField.tap()
        issuerField.typeText("Draft\n")

        let bar = app.navigationBars.firstMatch
        dragSheetDown(from: bar)
        assertDiscardActionSheet()
        app.sheets.buttons["Cancel"].tap()
        XCTAssertEqual(issuerField.value as? String, "Draft", "Cancel keeps the input\n\(app.debugDescription)")
    }

    func testDeleteTokenIsConfirmedWithActionSheet() throws {
        try reachMainScreen()
        addToken(issuer: "DeleteMe", account: "del@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        let row = app.staticTexts["DeleteMe"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.swipeLeft()
        button(containing: "Delete").tap()
        XCTAssertTrue(app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 5),
                      "Deleting a token asks for the PIN first\n\(app.debugDescription)")
        enterPIN()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Deletion is confirmed with an action sheet\n\(app.debugDescription)")
        XCTAssertTrue(sheet.buttons["Cancel"].exists, "The action sheet has a visible Cancel\n\(app.debugDescription)")
        sheet.buttons["Cancel"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 3), "Cancel keeps the token")

        row.swipeLeft()
        button(containing: "Delete").tap()
        XCTAssertTrue(app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 5), app.debugDescription)
        enterPIN()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        app.sheets.buttons["Delete"].tap()
        XCTAssertTrue(waitForDisappearance(row), app.debugDescription)
    }
}
