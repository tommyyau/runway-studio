import XCTest
@testable import RunwayStudioKit

final class StudioBarLayoutTests: XCTestCase {
    func testBarsAreInsetAndClippedToViewport() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let view = DateInterval(start: base.addingTimeInterval(20), end: base.addingTimeInterval(80))
        let bar = StudioBarLayout.inset(start: base, end: base.addingTimeInterval(100), within: view)
        XCTAssertEqual(bar.start.timeIntervalSince(base), 28.4, accuracy: 0.001)
        XCTAssertEqual(bar.end.timeIntervalSince(base), 71.6, accuracy: 0.001)
    }
    func testAdjacentBarsHaveVisibleSpace() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let view = DateInterval(start: base, duration: 600)
        let first = StudioBarLayout.inset(start: base, end: base.addingTimeInterval(300), within: view)
        let second = StudioBarLayout.inset(start: base.addingTimeInterval(300), end: view.end, within: view)
        XCTAssertLessThan(first.end, second.start)
    }
}
