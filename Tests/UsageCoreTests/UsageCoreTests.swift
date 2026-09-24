import XCTest
@testable import UsageCore

final class UsageCoreTests: XCTestCase {
    func testRateLimitFetchErrorProvidesActionableCodexLaunchHint() {
        let error = CodexUsageClientError.serverError(
            "failed to fetch codex rate limits: error sending request"
        )

        XCTAssertEqual(
            error.errorDescription,
            "Codex 尚未就绪。请先打开 Codex/ChatGPT 并确认已登录，然后返回刷新。"
        )
    }

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

    func testCustomDailyAlertLevelsAndProportionalScaling() {
        let thresholds = DailyAlertThresholds.default.scaled(toBaseCap: 15)
        XCTAssertEqual(thresholds.notice, 3.8, accuracy: 0.0001)
        XCTAssertEqual(thresholds.reminder, 7.5, accuracy: 0.0001)
        XCTAssertEqual(thresholds.high, 11.3, accuracy: 0.0001)
        XCTAssertEqual(thresholds.baseCap, 15, accuracy: 0.0001)
        XCTAssertEqual(
            DailyUsagePolicy.level(for: 7.5, dailyCap: 15, thresholds: thresholds),
            .reminder
        )
        XCTAssertEqual(
            DailyUsagePolicy.notificationThresholds(
                dailyCap: 18,
                thresholds: thresholds
            ),
            [3.8, 7.5, 11.3, 15, 18]
        )
    }

    func testQuotaResetDoesNotProduceNegativeDailyUsage() {
        XCTAssertEqual(DailyUsagePolicy.increase(baseline: 90, current: 2), 0)
    }

    func testUnusedSustainableBudgetRollsIntoNextDay() {
        let budget = RolloverBudgetCalculator.calculate(
            windowDurationMins: 10_080,
            yesterdayUsedPercent: 7,
            sourceDay: "2026-09-21",
            yesterdayUsageSource: .localDailySnapshots
        )

        XCTAssertEqual(budget.sustainableDailyBudgetPercent, 14.285714, accuracy: 0.0001)
        XCTAssertEqual(budget.baseDailyCapPercent, 20, accuracy: 0.0001)
        XCTAssertEqual(budget.carriedPercent, 7.285714, accuracy: 0.0001)
        XCTAssertEqual(budget.todayAvailablePercent, 27.285714, accuracy: 0.0001)
        XCTAssertEqual(budget.yesterdayUsageSource, .localDailySnapshots)
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

    func testWindowBaselineCanProvideMarkedYesterdayEstimate() {
        let budget = RolloverBudgetCalculator.calculate(
            windowDurationMins: 10_080,
            yesterdayUsedPercent: 13,
            sourceDay: "2026-09-21",
            yesterdayUsageSource: .windowBaselineEstimate
        )

        XCTAssertEqual(budget.carriedPercent, 1.285714, accuracy: 0.0001)
        XCTAssertEqual(budget.todayAvailablePercent, 21.285714, accuracy: 0.0001)
        XCTAssertEqual(budget.yesterdayUsageSource, .windowBaselineEstimate)
    }

    func testMissingRolloverCacheIsRecalculatedWhenBaselineBecomesAvailable() {
        XCTAssertFalse(
            RolloverBudgetCachePolicy.shouldReuseCachedBudget(
                cachedHasYesterdayData: false,
                canDeriveYesterdayDataNow: true
            )
        )
        XCTAssertTrue(
            RolloverBudgetCachePolicy.shouldReuseCachedBudget(
                cachedHasYesterdayData: false,
                canDeriveYesterdayDataNow: false
            )
        )
        XCTAssertTrue(
            RolloverBudgetCachePolicy.shouldReuseCachedBudget(
                cachedHasYesterdayData: true,
                canDeriveYesterdayDataNow: true
            )
        )
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

    func testMonthToDateTokenAggregationUsesAdaptedLocalDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 1)
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
                DailyTokenUsage(startDate: "2026-08-30", tokens: 100),
                DailyTokenUsage(startDate: "2026-08-31", tokens: 900),
            ]
        )

        XCTAssertEqual(
            usage.monthToDateTokens(through: referenceDate, calendar: calendar),
            900
        )
        XCTAssertEqual(
            usage.peakDailyTokensThisMonth(through: referenceDate, calendar: calendar),
            900
        )
        XCTAssertEqual(
            usage.latestUsageDate(through: referenceDate, calendar: calendar),
            "2026-08-31"
        )
        XCTAssertEqual(
            usage.adaptedDateKey(
                for: usage.latestDailyBucket!,
                through: referenceDate,
                calendar: calendar
            ),
            "2026-09-01"
        )
    }

    func testTodayAndYesterdayUseLatestTwoServerBuckets() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 23)
        )!
        let usage = AccountTokenUsage(
            summary: TokenUsageSummary(
                lifetimeTokens: nil,
                peakDailyTokens: nil,
                longestRunningTurnSec: nil,
                currentStreakDays: nil,
                longestStreakDays: nil
            ),
            dailyUsageBuckets: [
                DailyTokenUsage(startDate: "2026-09-21", tokens: 300),
                DailyTokenUsage(startDate: "2026-09-22", tokens: 900),
            ]
        )

        XCTAssertEqual(usage.todayTokens(), 900)
        XCTAssertEqual(usage.yesterdayTokens(), 300)
        XCTAssertEqual(
            usage.adaptedDateKey(
                for: usage.latestDailyBucket!,
                through: referenceDate,
                calendar: calendar
            ),
            "2026-09-23"
        )
        XCTAssertEqual(
            usage.adaptedDateKey(
                for: usage.previousDailyBucket!,
                through: referenceDate,
                calendar: calendar
            ),
            "2026-09-22"
        )
    }

    func testLatestSevenBucketsMapToConsecutiveLocalDaysEndingToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 25)
        )!
        let usage = AccountTokenUsage(
            summary: TokenUsageSummary(
                lifetimeTokens: nil,
                peakDailyTokens: nil,
                longestRunningTurnSec: nil,
                currentStreakDays: nil,
                longestStreakDays: nil
            ),
            dailyUsageBuckets: [
                DailyTokenUsage(startDate: "2026-09-02", tokens: 100),
                DailyTokenUsage(startDate: "2026-09-05", tokens: 200),
                DailyTokenUsage(startDate: "2026-09-11", tokens: 300),
                DailyTokenUsage(startDate: "2026-09-14", tokens: 400),
                DailyTokenUsage(startDate: "2026-09-16", tokens: 500),
                DailyTokenUsage(startDate: "2026-09-22", tokens: 600),
                DailyTokenUsage(startDate: "2026-09-24", tokens: 700),
            ]
        )

        let adaptedDates = usage.orderedDailyUsageBuckets.map {
            usage.adaptedDateKey(for: $0, through: referenceDate, calendar: calendar)
        }
        XCTAssertEqual(
            adaptedDates,
            [
                "2026-09-19",
                "2026-09-20",
                "2026-09-21",
                "2026-09-22",
                "2026-09-23",
                "2026-09-24",
                "2026-09-25",
            ]
        )
    }

    func testResolvesUserSelectedCodexExecutable() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let application = temporaryRoot.appendingPathComponent("ChatGPT.app", isDirectory: true)
        let resources = application.appendingPathComponent("Contents/Resources", isDirectory: true)
        let mockExecutable = resources.appendingPathComponent("codex")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        try FileManager.default.createDirectory(
            at: resources,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/bin/echo"),
            to: mockExecutable
        )

        XCTAssertEqual(
            CodexAppServerClient.resolveExecutable(fromUserSelection: application),
            mockExecutable
        )
        XCTAssertEqual(
            CodexAppServerClient.resolveExecutable(
                fromUserSelection: URL(fileURLWithPath: "/bin/echo")
            ),
            URL(fileURLWithPath: "/bin/echo")
        )
    }

    func testRecognizesCodexAuthenticationDirectory() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )
        XCTAssertFalse(CodexAppServerClient.containsCodexAuthentication(temporaryRoot))

        let authFile = temporaryRoot.appendingPathComponent("auth.json")
        XCTAssertTrue(FileManager.default.createFile(atPath: authFile.path, contents: Data()))
        XCTAssertTrue(CodexAppServerClient.containsCodexAuthentication(temporaryRoot))
    }
}
