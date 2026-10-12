import XCTest

final class PasscodeNoticeUITests: KeyaUITestCase {
    private let notice = "Set a device passcode in iOS Settings to keep your tokens protected."

    func testNoticeIsHiddenWhenTheDeviceHasAPasscode() throws {
        try reachMainScreen()
        XCTAssertFalse(app.staticTexts[notice].waitForExistence(timeout: 2), app.debugDescription)
    }

    func testNoticeIsShownWhenTheDeviceHasNoPasscode() throws {
        app.terminate()
        app.launchArguments += ["-UITestNoDevicePasscode"]
        app.launch()
        try reachMainScreen()
        XCTAssertTrue(app.staticTexts[notice].waitForExistence(timeout: 5), app.debugDescription)
    }
}
