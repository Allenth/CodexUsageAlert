import Foundation

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let remainingPercent: Double
    public let windowDurationMins: Double
    public let resetsAt: Date
    public let planType: String?
    public let fetchedAt: Date

    public init(
        usedPercent: Double,
        windowDurationMins: Double,
        resetsAt: Date,
        planType: String?,
        fetchedAt: Date = Date()
    ) {
        self.usedPercent = min(100, max(0, usedPercent))
        self.remainingPercent = min(100, max(0, 100 - usedPercent))
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
        self.planType = planType
        self.fetchedAt = fetchedAt
    }

    public var windowDays: Double {
        windowDurationMins / 1_440
    }
}

public struct TokenUsageSummary: Codable, Equatable, Sendable {
    public let lifetimeTokens: Int64?
    public let peakDailyTokens: Int64?
    public let longestRunningTurnSec: Int64?
    public let currentStreakDays: Int?
    public let longestStreakDays: Int?

    public init(
        lifetimeTokens: Int64?,
        peakDailyTokens: Int64?,
        longestRunningTurnSec: Int64?,
        currentStreakDays: Int?,
        longestStreakDays: Int?
    ) {
        self.lifetimeTokens = lifetimeTokens
        self.peakDailyTokens = peakDailyTokens
        self.longestRunningTurnSec = longestRunningTurnSec
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
    }
}

public struct DailyTokenUsage: Codable, Equatable, Sendable, Identifiable {
    public var id: String { startDate }
    public let startDate: String
    public let tokens: Int64

    public init(startDate: String, tokens: Int64) {
        self.startDate = startDate
        self.tokens = tokens
    }
}

public struct AccountTokenUsage: Codable, Equatable, Sendable {
    public let summary: TokenUsageSummary
    public let dailyUsageBuckets: [DailyTokenUsage]

    public init(summary: TokenUsageSummary, dailyUsageBuckets: [DailyTokenUsage]) {
        self.summary = summary
        self.dailyUsageBuckets = dailyUsageBuckets
    }

    public func monthToDateTokens(
        through date: Date = Date(),
        calendar: Calendar = .current
    ) -> Int64? {
        let buckets = monthToDateBuckets(through: date, calendar: calendar)
        guard !buckets.isEmpty else { return nil }
        return buckets.reduce(0) { $0 + $1.tokens }
    }

    public func peakDailyTokensThisMonth(
        through date: Date = Date(),
        calendar: Calendar = .current
    ) -> Int64? {
        monthToDateBuckets(through: date, calendar: calendar)
            .map(\.tokens)
            .max()
    }

    public func latestUsageDate(
        through date: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        monthToDateBuckets(through: date, calendar: calendar)
            .map(\.startDate)
            .max()
    }

    private func monthToDateBuckets(
        through date: Date,
        calendar: Calendar
    ) -> [DailyTokenUsage] {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return [] }

        let monthPrefix = String(format: "%04d-%02d-", year, month)
        let todayKey = String(format: "%04d-%02d-%02d", year, month, day)
        return dailyUsageBuckets.filter {
            $0.startDate.hasPrefix(monthPrefix) && $0.startDate <= todayKey
        }
    }
}

public struct UsageDashboardSnapshot: Sendable {
    public let quota: UsageSnapshot
    public let tokenUsage: AccountTokenUsage?
    public let tokenUsageError: String?

    public init(
        quota: UsageSnapshot,
        tokenUsage: AccountTokenUsage?,
        tokenUsageError: String? = nil
    ) {
        self.quota = quota
        self.tokenUsage = tokenUsage
        self.tokenUsageError = tokenUsageError
    }
}

public enum TokenUnitStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case chinese
    case english

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chinese: return "中文（万 / 亿）"
        case .english: return "English（K / M / B）"
        }
    }
}

public enum TokenCountFormatter {
    public static func compact(
        _ value: Int64?,
        style: TokenUnitStyle = .english
    ) -> String {
        guard let value else { return "--" }
        let magnitude = Double(value)
        let units: [(threshold: Double, suffix: String)]
        switch style {
        case .chinese:
            units = [
                (1_000_000_000_000, "万亿"),
                (100_000_000, "亿"),
                (10_000, "万"),
            ]
        case .english:
            units = [
                (1_000_000_000_000, "T"),
                (1_000_000_000, "B"),
                (1_000_000, "M"),
                (1_000, "K"),
            ]
        }

        guard let unit = units.first(where: { magnitude >= $0.threshold }) else {
            return value.formatted(.number.grouping(.automatic))
        }

        let scaled = magnitude / unit.threshold
        let precision = scaled >= 100 ? 0 : 1
        return scaled.formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .grouping(.never)
                .precision(.fractionLength(0...precision))
        ) + unit.suffix
    }
}

public enum UsageAlertLevel: Int, Codable, Comparable, Sendable {
    case normal = 0
    case notice = 5
    case reminder = 10
    case high = 15
    case cap = 20

    public static func < (lhs: UsageAlertLevel, rhs: UsageAlertLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .normal: return "正常"
        case .notice: return "用量提醒"
        case .reminder: return "用量偏高"
        case .high: return "接近每日上限"
        case .cap: return "达到每日上限"
        }
    }
}

public enum DailyUsagePolicy {
    public static let defaultThresholds: [Double] = [5, 10, 15, 20]

    public static func increase(baseline: Double, current: Double) -> Double {
        guard current >= baseline else { return 0 }
        return current - baseline
    }

    public static func level(for increase: Double, dailyCap: Double = 20) -> UsageAlertLevel {
        if increase >= max(20, dailyCap) { return .cap }
        if increase >= 15 { return .high }
        if increase >= 10 { return .reminder }
        if increase >= 5 { return .notice }
        return .normal
    }

    public static func notificationThresholds(dailyCap: Double) -> [Double] {
        let cap = max(20, dailyCap)
        if cap > 20 { return defaultThresholds + [cap] }
        return defaultThresholds
    }
}

public struct DailyBudgetRollover: Equatable, Sendable {
    public let sustainableDailyBudgetPercent: Double
    public let baseDailyCapPercent: Double
    public let yesterdayUsedPercent: Double?
    public let carriedPercent: Double
    public let todayAvailablePercent: Double
    public let sourceDay: String?

    public var hasYesterdayData: Bool {
        yesterdayUsedPercent != nil
    }

    public init(
        sustainableDailyBudgetPercent: Double,
        baseDailyCapPercent: Double,
        yesterdayUsedPercent: Double?,
        carriedPercent: Double,
        todayAvailablePercent: Double,
        sourceDay: String?
    ) {
        self.sustainableDailyBudgetPercent = sustainableDailyBudgetPercent
        self.baseDailyCapPercent = baseDailyCapPercent
        self.yesterdayUsedPercent = yesterdayUsedPercent
        self.carriedPercent = carriedPercent
        self.todayAvailablePercent = todayAvailablePercent
        self.sourceDay = sourceDay
    }
}

public enum RolloverBudgetCalculator {
    public static func sustainableDailyBudget(windowDurationMins: Double) -> Double {
        guard windowDurationMins > 0 else { return 0 }
        return min(100, 100 / (windowDurationMins / 1_440))
    }

    public static func calculate(
        windowDurationMins: Double,
        yesterdayUsedPercent: Double?,
        sourceDay: String?,
        baseDailyCapPercent: Double = 20
    ) -> DailyBudgetRollover {
        let sustainable = sustainableDailyBudget(windowDurationMins: windowDurationMins)
        let baseCap = min(100, max(0, baseDailyCapPercent))
        let used = yesterdayUsedPercent.map { min(100, max(0, $0)) }
        let carried = used.map { max(0, sustainable - $0) } ?? 0

        return DailyBudgetRollover(
            sustainableDailyBudgetPercent: sustainable,
            baseDailyCapPercent: baseCap,
            yesterdayUsedPercent: used,
            carriedPercent: carried,
            todayAvailablePercent: min(100, baseCap + carried),
            sourceDay: used == nil ? nil : sourceDay
        )
    }
}
