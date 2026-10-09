import XCTest

final class CameraAccessUITests: KeyaUITestCase {
    override func tearDown() {
        app.resetAuthorizationStatus(for: .camera)
        super.tearDown()
    }

    func testDeniedCameraOffersOpenSettings() throws {
        app.terminate()
        app.resetAuthorizationStatus(for: .camera)
        app.launch()
        try reachMainScreen()

        app.buttons["Add"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let prompt = springboard.alerts.firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "The camera permission prompt should appear")
        prompt.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.buttons["Open Settings"].waitForExistence(timeout: 5),
                      "Denied camera access offers a direct way to Settings\n\(app.debugDescription)")
    }
}
