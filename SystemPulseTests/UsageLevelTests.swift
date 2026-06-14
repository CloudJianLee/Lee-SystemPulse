import Testing
@testable import SystemPulse

struct UsageLevelTests {
    @Test func thresholdBoundaries() {
        #expect(UsageLevel(0.0) == .normal)
        #expect(UsageLevel(0.7999) == .normal)
        #expect(UsageLevel(0.80) == .warning)
        #expect(UsageLevel(0.8999) == .warning)
        #expect(UsageLevel(0.90) == .critical)
        #expect(UsageLevel(0.9499) == .critical)
        #expect(UsageLevel(0.95) == .severe)
        #expect(UsageLevel(1.0) == .severe)
    }
}
