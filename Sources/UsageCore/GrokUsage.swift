import Foundation

public enum GrokUsageStatus: String, Sendable {
    case ready, missing, stale, invalid, disabled

    public var title: String {
        switch self {
        case .ready: return "已接入"
        case .missing: return "未接入"
        case .stale: return "数据过期"
        case .invalid: return "数据无效"
        case .disabled: return "已关闭"
        }
    }
}

public struct GrokUsageSnapshot: Codable, Equatable, Sendable {
    public let service: String
    public let usedPercent: Double
    public let resetAt: Date
    public let plan: String
    public let tasksToday: Int
    public let tasksPeriod: Int
    public let updatedAt: Date

    public init(usedPercent: Double, resetAt: Date, plan: String, tasksToday: Int,
                tasksPeriod: Int, updatedAt: Date = Date()) {
        service = "grok-bot"
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.plan = plan
        self.tasksToday = tasksToday
        self.tasksPeriod = tasksPeriod
        self.updatedAt = updatedAt
    }

    public var remainingPercent: Double { max(0, 100 - usedPercent) }

    public func status(at now: Date = Date()) -> GrokUsageStatus {
        guard service == "grok-bot", usedPercent.isFinite, (0...100).contains(usedPercent),
              tasksToday >= 0, tasksPeriod >= 0,
              updatedAt.timeIntervalSince(now) <= 300 else { return .invalid }
        return now.timeIntervalSince(updatedAt) > 2 * 60 * 60 ? .stale : .ready
    }
}

public enum GrokUsageReadSchedule {
    /// Recompute from local wall time after each read, wake, or clock change.
    public static func nextRead(after now: Date, calendar: Calendar = .current) -> Date? {
        [20, 50].compactMap { minute in
            calendar.nextDate(after: now, matching: DateComponents(minute: minute, second: 0),
                              matchingPolicy: .nextTime)
        }.min()
    }
}

public enum GrokUsageError: LocalizedError {
    case invalidData, missingResetDate
    public var errorDescription: String? {
        switch self {
        case .invalidData: return "Grok Bot 数据无效，请检查百分比、计数和 ISO8601 日期。"
        case .missingResetDate: return "首次手动填写时，请提供 Grok Bot 的周期重置时间。"
        }
    }
}

public struct GrokUsageReadResult: Sendable {
    public let snapshot: GrokUsageSnapshot?
    public let status: GrokUsageStatus
    public let message: String?
}

public enum GrokUsageFile {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexUsageAlert/grok-usage.json")
    }

    public static func decode(_ data: Data) throws -> GrokUsageSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else { throw GrokUsageError.invalidData }
            return date
        }
        return try decoder.decode(GrokUsageSnapshot.self, from: data)
    }

    public static func read(from url: URL = defaultURL, now: Date = Date()) -> GrokUsageReadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return GrokUsageReadResult(snapshot: nil, status: .missing, message: nil)
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 1_048_576 else {
                throw GrokUsageError.invalidData
            }
            let snapshot = try decode(Data(contentsOf: url))
            let status = snapshot.status(at: now)
            return GrokUsageReadResult(snapshot: status == .invalid ? nil : snapshot,
                                       status: status,
                                       message: status == .invalid ? GrokUsageError.invalidData.localizedDescription : nil)
        } catch {
            return GrokUsageReadResult(snapshot: nil, status: .invalid,
                                       message: GrokUsageError.invalidData.localizedDescription)
        }
    }

    public static func write(_ snapshot: GrokUsageSnapshot, to url: URL = defaultURL,
                             now: Date = Date()) throws {
        guard snapshot.status(at: now) == .ready else { throw GrokUsageError.invalidData }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

/// One state per service, persisted between launches. First sample of each local
/// day establishes a baseline. A cycle reset rebases without rearming alerts.
public struct DailyUsageTracker: Codable, Equatable, Sendable {
    public private(set) var day: String = ""
    public private(set) var baseline: Double = 0
    public private(set) var lastUsedPercent: Double = 0
    public private(set) var cycleResetAt: Date?
    public private(set) var increase: Double = 0
    public private(set) var notifiedThresholds: Set<Int> = []

    public init() {}

    public init(day: String, baseline: Double, notifiedThresholds: Set<Int>) {
        self.day = day
        self.baseline = baseline
        self.lastUsedPercent = baseline
        self.notifiedThresholds = notifiedThresholds
    }

    @discardableResult
    public mutating func record(usedPercent: Double, resetAt: Date, at now: Date = Date(),
                                calendar: Calendar = .current) -> [Int] {
        guard usedPercent.isFinite, (0...100).contains(usedPercent) else { return [] }
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let newDay = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        if day != newDay {
            day = newDay
            baseline = usedPercent
            increase = 0
            notifiedThresholds = []
        } else if (cycleResetAt != nil && cycleResetAt != resetAt) || usedPercent < lastUsedPercent {
            // A decrease may be a cycle reset or a manual correction; do not
            // infer consumption that cannot be observed.
            baseline = usedPercent
            increase = 0
        } else {
            increase = max(0, usedPercent - baseline)
        }
        lastUsedPercent = usedPercent
        cycleResetAt = resetAt
        let crossed = DailyUsagePolicy.defaultThresholds.map(Int.init)
            .filter { increase >= Double($0) && !notifiedThresholds.contains($0) }
        notifiedThresholds.formUnion(crossed)
        return crossed
    }
}

public enum UsageAggregation {
    public static func maximum(codex: Double?, codexEnabled: Bool,
                               grok: Double?, grokEnabled: Bool) -> Double? {
        [codexEnabled ? codex : nil, grokEnabled ? grok : nil]
            .compactMap { $0 }.filter { $0.isFinite && (0...100).contains($0) }.max()
    }
}
