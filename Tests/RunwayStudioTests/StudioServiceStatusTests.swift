import Foundation
import XCTest
@testable import RunwayStudioKit

private actor StatusFixture {
    var count = 0
    func response(_ request: URLRequest) throws -> (Data, URLResponse) {
        count += 1
        guard count == 1 else { throw URLError(.timedOut) }
        let data = Data(#"{"status":{"indicator":"minor","description":"Partial outage"}}"#.utf8)
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

final class StudioServiceStatusTests: XCTestCase {
    func testCacheAndFailedRefreshKeepLastKnownStatusMarkedStale() async {
        let fixture = StatusFixture()
        let monitor = StudioServiceStatusMonitor(interval: 300) { request in try await fixture.response(request) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = await monitor.status(provider: "claude", now: now)
        XCTAssertEqual(first?.description, "Partial outage")
        let cached = await monitor.status(provider: "claude", now: now.addingTimeInterval(100))
        XCTAssertEqual(cached, first)
        let failed = await monitor.status(provider: "claude", now: now.addingTimeInterval(301))
        XCTAssertEqual(failed?.checkedAt, now)
        XCTAssertEqual(failed?.failedAt, now.addingTimeInterval(301))
        XCTAssertEqual(failed?.isStale, true)
    }

    func testFailureWithoutCachedStatusIsUnavailable() async {
        let monitor = StudioServiceStatusMonitor { _ in throw URLError(.timedOut) }
        let status = await monitor.status(provider: "codex")
        XCTAssertNil(status)
    }
}
