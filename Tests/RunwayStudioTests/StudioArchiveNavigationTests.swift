import XCTest
@testable import RunwayStudioKit

final class StudioArchiveNavigationTests: XCTestCase {
    func testWindowsContainOnlyObservedReadingsForRequestedAccount() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func reading(_ account: String, _ day: Double, _ reset: Double) -> StudioReading {
            StudioReading(account: account, date: base.addingTimeInterval(day * 86400),
                          reset: base.addingTimeInterval(reset * 86400), duration: 604800, remaining: 50)
        }
        let archive = StudioArchive(readings: [reading("a", 1, 7), reading("b", 8, 14),
                                               reading("a", 2, 7), reading("a", 22, 28)])
        let windows = archive.windows(account: "a")
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows.map(\.readings.count), [2, 1])
        XCTAssertEqual(windows.map(\.reset), [base.addingTimeInterval(7 * 86400), base.addingTimeInterval(28 * 86400)])
        XCTAssertTrue(archive.windows(account: "missing").isEmpty)
    }

    func testSlightResetRoundingDoesNotSplitAWindow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let readings = [0.0, 1.0].map { offset in
            StudioReading(account: "a", date: now.addingTimeInterval(offset * 60),
                          reset: now.addingTimeInterval(1000 + offset), duration: 604800, remaining: 80)
        }
        XCTAssertEqual(StudioArchive(readings: readings).windows(account: "a").first?.readings.count, 2)
    }
    func testCompletedWindowsCoalesceSubsecondResetRounding() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = StudioReading(account: "a", date: now.addingTimeInterval(-200),
            reset: now.addingTimeInterval(-99.51), duration: 604800, remaining: 60)
        let last = StudioReading(account: "a", date: now.addingTimeInterval(-150),
            reset: now.addingTimeInterval(-99.49), duration: 604800, remaining: 50)
        let result = StudioArchive(readings: [first, last]).completed(account: "a", now: now)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.remaining, 50)
    }

}
