import XCTest
@testable import Keya_Authenticator

@MainActor
final class NextCodeWindowTests: XCTestCase {
    private func time(_ secondsIntoPeriod: Double, period: Int) -> Date {
        let periodStart = 1_800_000_000 - 1_800_000_000 % period
        return Date(timeIntervalSince1970: Double(periodStart) + secondsIntoPeriod)
    }

    func testHiddenBeforeTheLastTenSeconds() {
        XCTAssertFalse(TokenRowView.showsNextCode(at: time(0, period: 30), period: 30))
        XCTAssertFalse(TokenRowView.showsNextCode(at: time(19.9, period: 30), period: 30))
        XCTAssertFalse(TokenRowView.showsNextCode(at: time(49.9, period: 60), period: 60))
    }

    func testShownInTheLastTenSeconds() {
        XCTAssertTrue(TokenRowView.showsNextCode(at: time(20, period: 30), period: 30))
        XCTAssertTrue(TokenRowView.showsNextCode(at: time(29.9, period: 30), period: 30))
        XCTAssertTrue(TokenRowView.showsNextCode(at: time(50, period: 60), period: 60))
        XCTAssertTrue(TokenRowView.showsNextCode(at: time(59.9, period: 60), period: 60))
    }
}
