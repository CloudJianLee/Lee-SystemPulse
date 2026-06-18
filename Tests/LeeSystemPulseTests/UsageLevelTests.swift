import XCTest
@testable import LeeSystemPulse

final class UsageLevelTests: XCTestCase {
    func testThresholdBoundaries() {
        XCTAssertEqual(UsageLevel(0.0), .normal)
        XCTAssertEqual(UsageLevel(0.7999), .normal)
        XCTAssertEqual(UsageLevel(0.80), .warning)
        XCTAssertEqual(UsageLevel(0.8999), .warning)
        XCTAssertEqual(UsageLevel(0.90), .critical)
        XCTAssertEqual(UsageLevel(0.9499), .critical)
        XCTAssertEqual(UsageLevel(0.95), .severe)
        XCTAssertEqual(UsageLevel(1.0), .severe)
    }

    func testPercentFormatting() {
        XCTAssertEqual(percent(0.0), "0%")
        XCTAssertEqual(percent(0.5), "50%")
        XCTAssertEqual(percent(1.0), "100%")
        XCTAssertEqual(percent(0.999), "100%")
        XCTAssertEqual(percent(0.001), "0%")
        XCTAssertEqual(percent(0.756), "76%")
    }

    @MainActor
    func testOverallLevelDefault() {
        let monitor = SystemMonitor()
        XCTAssertEqual(monitor.overallLevel, .normal)
    }
}
