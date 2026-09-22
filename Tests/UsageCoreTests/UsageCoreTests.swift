import XCTest
@testable import UsageCore

final class UsageCoreTests: XCTestCase {
    func testSnapshotClampsPercentages() {
        let snapshot = UsageSnapshot(
            usedPercent: 120,
            windowDurationMins: 10_080,
            resetsAt: Date(timeIntervalSince1970: 100),
            planType: nil
        )
        XCTAssertEqual(snapshot.usedPercent, 100)
        XCTAssertEqual(snapshot.remainingPercent, 0)
        XCTAssertEqual(snapshot.windowDays, 7)
    }

    func testDailyAlertLevels() {
        XCTAssertEqual(DailyUsagePolicy.level(for: 4.99), .normal)
        XCTAssertEqual(DailyUsagePolicy.level(for: 5), .notice)
        XCTAssertEqual(DailyUsagePolicy.level(for: 10), .reminder)
        XCTAssertEqual(DailyUsagePolicy.level(for: 15), .high)
        XCTAssertEqual(DailyUsagePolicy.level(for: 20), .cap)
        XCTAssertEqual(DailyUsagePolicy.level(for: 20, dailyCap: 27.3), .high)
        XCTAssertEqual(DailyUsagePolicy.level(for: 27.3, dailyCap: 27.3), .cap)
    }

    func testQuotaResetDoesNotProduceNegativeDailyUsage() {
        XCTAssertEqual(DailyUsagePolicy.increase(baseline: 90, current: 2), 0)
    }

    func testUnusedSustainableBudgetRollsIntoNextDay() {
        let budget = RolloverBudgetCalculator.calculate(
            windowDurationMins: 10_080,
            yesterdayUsedPercent: 7,
            sourceDay: "2026-09-21"
        )

        XCTAssertEqual(budget.sustainableDailyBudgetPercent, 14.285714, accuracy: 0.0001)
        XCTAssertEqual(budget.baseDailyCapPercent, 20, accuracy: 0.0001)
        XCTAssertEqual(budget.carriedPercent, 7.285714, accuracy: 0.0001)
        XCTAssertEqual(budget.todayAvailablePercent, 27.285714, accuracy: 0.0001)
        XCTAssertTrue(budget.hasYesterdayData)
    }

    func testMissingYesterdayDataDoesNotCreateRollover() {
        let budget = RolloverBudgetCalculator.calculate(
            windowDurationMins: 10_080,
            yesterdayUsedPercent: nil,
            sourceDay: nil
        )

        XCTAssertEqual(budget.carriedPercent, 0)
        XCTAssertEqual(budget.todayAvailablePercent, 20, accuracy: 0.0001)
        XCTAssertFalse(budget.hasYesterdayData)
    }

    func testDailyCapThresholdIncludesRolloverCap() {
        XCTAssertEqual(
            DailyUsagePolicy.notificationThresholds(dailyCap: 27.3),
            [5, 10, 15, 20, 27.3]
        )
    }

    func testCompactTokenFormatting() {
        XCTAssertEqual(TokenCountFormatter.compact(nil), "--")
        XCTAssertEqual(TokenCountFormatter.compact(999), "999")
        XCTAssertEqual(TokenCountFormatter.compact(1_250), "1.2K")
        XCTAssertEqual(TokenCountFormatter.compact(16_340_000_000), "16.3B")
        XCTAssertEqual(
            TokenCountFormatter.compact(24_000_000, style: .chinese),
            "2400万"
        )
        XCTAssertEqual(
            TokenCountFormatter.compact(2_400_000_000, style: .chinese),
            "24亿"
        )
        XCTAssertEqual(
            TokenCountFormatter.compact(16_340_000_000, style: .chinese),
            "163亿"
        )
    }

    func testParsesTokenUsageWithNullableSummaryValues() throws {
        let response: [String: Any] = [
            "result": [
                "summary": [
                    "lifetimeTokens": 1_234_567,
                    "peakDailyTokens": NSNull(),
                    "longestRunningTurnSec": 540,
                    "currentStreakDays": 8,
                    "longestStreakDays": 14,
                ],
                "dailyUsageBuckets": [
                    ["startDate": "2026-06-18", "tokens": 12_345],
                ],
            ],
        ]

        let usage = try CodexAppServerClient.parseTokenUsage(response)
        XCTAssertEqual(usage.summary.lifetimeTokens, 1_234_567)
        XCTAssertNil(usage.summary.peakDailyTokens)
        XCTAssertEqual(usage.summary.currentStreakDays, 8)
        XCTAssertEqual(usage.dailyUsageBuckets.first?.tokens, 12_345)
    }

    func testMonthToDateTokenAggregationExcludesOtherMonthsAndFutureDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 22)
        )!
        let usage = AccountTokenUsage(
            summary: TokenUsageSummary(
                lifetimeTokens: 9_999,
                peakDailyTokens: 5_000,
                longestRunningTurnSec: nil,
                currentStreakDays: nil,
                longestStreakDays: nil
            ),
            dailyUsageBuckets: [
                DailyTokenUsage(startDate: "2026-08-31", tokens: 100),
                DailyTokenUsage(startDate: "2026-09-01", tokens: 200),
                DailyTokenUsage(startDate: "2026-09-20", tokens: 500),
                DailyTokenUsage(startDate: "2026-09-23", tokens: 900),
            ]
        )

        XCTAssertEqual(
            usage.monthToDateTokens(through: referenceDate, calendar: calendar),
            700
        )
        XCTAssertEqual(
            usage.peakDailyTokensThisMonth(through: referenceDate, calendar: calendar),
            500
        )
        XCTAssertEqual(
            usage.latestUsageDate(through: referenceDate, calendar: calendar),
            "2026-09-20"
        )
    }
}
