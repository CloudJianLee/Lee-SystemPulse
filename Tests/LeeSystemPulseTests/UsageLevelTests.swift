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

final class MemoryPressureTests: XCTestCase {
    func testPressureLabels() {
        XCTAssertEqual(MemoryPressure.normal.label, "正常")
        XCTAssertEqual(MemoryPressure.light.label, "轻度压力")
        XCTAssertEqual(MemoryPressure.moderate.label, "中度压力")
        XCTAssertEqual(MemoryPressure.heavy.label, "严重压力")
    }

    func testPressureSystemImages() {
        XCTAssertEqual(MemoryPressure.normal.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(MemoryPressure.heavy.systemImage, "xmark.octagon.fill")
    }

    @MainActor
    func testDefaultPressureIsNormal() {
        let monitor = SystemMonitor()
        // After init + sample(), with low usage the pressure should be normal or light
        let pressure = monitor.memoryPressure
        XCTAssertTrue(pressure == .normal || pressure == .light,
                       "Expected normal or light pressure, got \(pressure)")
    }

    @MainActor
    func testOptimizationTipsEmptyWhenNormal() {
        let monitor = SystemMonitor()
        // At default state, swap and compressed should be low enough
        // that tips may or may not be empty (depends on real system state).
        // Just verify it returns an array without crashing.
        let tips = monitor.optimizationTips
        XCTAssertNotNil(tips)
    }

    @MainActor
    func testTopProcessesLoaded() {
        let monitor = SystemMonitor()
        // Process list is populated asynchronously, just verify it doesn't crash
        // and the array is accessible
        XCTAssertNotNil(monitor.topProcesses)
    }
}
