import XCTest

final class PINErrorLayoutUITests: KeyaUITestCase {
    func testWrappedLockoutWarningIsCenteredWithinMargins() throws {
        app.terminate()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8), app.debugDescription)
        enterPIN()
        Thread.sleep(forTimeInterval: 1.0)
        enterPIN()
        XCTAssertTrue(app.buttons["plus"].waitForExistence(timeout: 8), app.debugDescription)

        app.terminate()
        app.launchArguments.removeAll { $0 == "-UITestResetState" }
        app.launch()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8), app.debugDescription)

        let warning = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Falsche PIN.'")).firstMatch
        for _ in 1 ... 6 where !warning.exists {
            app.typeText("000000")
            _ = warning.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(warning.exists, app.debugDescription)

        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(warning.frame.minX, screen.minX + 16, "\(warning.frame)")
        XCTAssertLessThanOrEqual(warning.frame.maxX, screen.maxX - 16, "\(warning.frame)")
        XCTAssertEqual(warning.frame.midX, screen.midX, accuracy: 2, "\(warning.frame)")
    }
}
