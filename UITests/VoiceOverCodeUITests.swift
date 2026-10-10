import XCTest

final class VoiceOverCodeUITests: KeyaUITestCase {
    func testRowValueCarriesTheCodeAndHidesItWhenCodesAreHidden() throws {
        try reachMainScreen()
        addToken(issuer: "VOTest", account: "vo@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        let row = element(labelContaining: "VOTest")
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        let shown = row.value as? String ?? ""
        XCTAssertNotNil(shown.range(of: #"^\d( \d){5}, \d{1,2} seconds? left$"#, options: .regularExpression),
                        "VoiceOver hears the code digit by digit and the time left: \(shown)\n\(app.debugDescription)")
        XCTAssertEqual(row.elementType, .button, "The row acts on tap, so VoiceOver announces it as a button")
        XCTAssertFalse(app.descendants(matching: .any)["Authentication code"].exists,
                       "The visible code must not be a separate VoiceOver element inside the row\n\(app.debugDescription)")

        openSettings(scrollingTo: "App lock")
        let hide = app.switches["Hide tokens"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5), app.debugDescription)
        hide.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["Close"].tap()

        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(row.value as? String, "Code hidden", app.debugDescription)
        XCTAssertEqual(row.elementType, .button, "A hidden code row still reveals on tap")
        XCTAssertFalse(app.buttons["Tap to reveal code"].exists,
                       "The hidden code must not be a separate VoiceOver element inside the row\n\(app.debugDescription)")
    }
}
