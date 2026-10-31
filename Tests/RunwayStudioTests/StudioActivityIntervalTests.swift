import XCTest
@testable import RunwayStudioKit

final class StudioActivityIntervalTests: XCTestCase {
    func testAcceptsExactRangeWithinBounds() {
        let origin = Date(timeIntervalSince1970: 1_700_000_000)
        let bounds = DateInterval(start: origin, duration: 3600)
        let result = StudioActivityInterval.bounded(start: origin.addingTimeInterval(125), end: origin.addingTimeInterval(251), within: bounds)
        XCTAssertEqual(result?.start, origin.addingTimeInterval(125))
        XCTAssertEqual(result?.end, origin.addingTimeInterval(251))
    }
    func testRejectsZeroReversedAndOutOfBoundsRanges() {
        let origin = Date(timeIntervalSince1970: 1_700_000_000)
        let bounds = DateInterval(start: origin, duration: 3600)
        XCTAssertNil(StudioActivityInterval.bounded(start: origin, end: origin, within: bounds))
        XCTAssertNil(StudioActivityInterval.bounded(start: origin.addingTimeInterval(20), end: origin, within: bounds))
        XCTAssertNil(StudioActivityInterval.bounded(start: origin.addingTimeInterval(-1), end: origin.addingTimeInterval(10), within: bounds))
        XCTAssertNil(StudioActivityInterval.bounded(start: origin, end: origin.addingTimeInterval(3601), within: bounds))
    }
}
