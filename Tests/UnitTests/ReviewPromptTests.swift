import XCTest
@testable import Keya_Authenticator

@MainActor
final class ReviewPromptTests: XCTestCase {
    func testAsksOnlyAfterEnoughUseAndOncePerVersion() {
        XCTAssertTrue(ReviewPrompt.shouldRequest(activeDays: 5, tokenCount: 2, currentVersion: "1.3.0", lastPromptedVersion: nil))
        XCTAssertTrue(ReviewPrompt.shouldRequest(activeDays: 9, tokenCount: 4, currentVersion: "1.3.0", lastPromptedVersion: "1.2.0"))
        XCTAssertFalse(ReviewPrompt.shouldRequest(activeDays: 4, tokenCount: 2, currentVersion: "1.3.0", lastPromptedVersion: nil))
        XCTAssertFalse(ReviewPrompt.shouldRequest(activeDays: 5, tokenCount: 1, currentVersion: "1.3.0", lastPromptedVersion: nil))
        XCTAssertFalse(ReviewPrompt.shouldRequest(activeDays: 5, tokenCount: 2, currentVersion: "1.3.0", lastPromptedVersion: "1.3.0"))
    }

    func testActiveDaysCountEachCalendarDayOnce() {
        let settings = AppSettings()
        settings.activeDayCount = 0
        settings.lastActiveDay = nil
        let calendar = Calendar.current
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 9))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 22))!
        let nextDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 8))!

        settings.recordActiveDay(on: morning)
        settings.recordActiveDay(on: evening)
        XCTAssertEqual(settings.activeDayCount, 1)

        settings.recordActiveDay(on: nextDay)
        XCTAssertEqual(settings.activeDayCount, 2)

        settings.activeDayCount = 0
        settings.lastActiveDay = nil
    }
}
