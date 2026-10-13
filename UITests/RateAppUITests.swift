import XCTest

final class RateAppUITests: KeyaUITestCase {
    func testSettingsOffersRatingTheApp() throws {
        try reachMainScreen()
        openSettings(scrollingTo: "App lock")

        let rate = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
            ? app.links["Rate Keya"]
            : app.buttons["Rate Keya"]
        for _ in 0 ..< 5 where !(rate.exists && rate.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(rate.exists && rate.isHittable, "Settings links to the App Store review page\n\(app.debugDescription)")
    }
}
