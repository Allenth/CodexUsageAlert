import XCTest
@testable import UsageCore

final class GrokUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var reset: Date { now.addingTimeInterval(86_400 * 7) }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func sample(_ value: Double = 18, updatedAt: Date? = nil,
                        tasksToday: Int = 2) -> GrokUsageSnapshot {
        GrokUsageSnapshot(usedPercent: value, resetAt: reset, plan: "Test",
                          tasksToday: tasksToday, tasksPeriod: 12, updatedAt: updatedAt ?? now)
    }

    func testDecodesBothISO8601DatePrecisions() throws {
        for date in ["2027-01-15T08:00:00Z", "2027-01-15T08:00:00.123Z"] {
            let data = Data("""
            {"service":"grok-bot","usedPercent":18,"resetAt":"\(date)","plan":"Test","tasksToday":2,"tasksPeriod":12,"updatedAt":"\(date)"}
            """.utf8)
            let value = try GrokUsageFile.decode(data)
            XCTAssertEqual(value.usedPercent, 18)
            XCTAssertEqual(value.tasksToday, 2)
            XCTAssertEqual(value.remainingPercent, 82)
        }
    }

    func testRejectsMalformedAndWrongService() throws {
        XCTAssertThrowsError(try GrokUsageFile.decode(Data("{}".utf8)))
        let json = """
        {"service":"wrong","usedPercent":18,"resetAt":"2027-01-15T08:00:00Z","plan":"Test","tasksToday":0,"tasksPeriod":0,"updatedAt":"2027-01-15T08:00:00Z"}
        """
        XCTAssertEqual(try GrokUsageFile.decode(Data(json.utf8)).status(at: now), .invalid)
        XCTAssertEqual(sample(-1).status(at: now), .invalid)
        XCTAssertEqual(sample(101).status(at: now), .invalid)
        XCTAssertEqual(sample(.nan).status(at: now), .invalid)
        XCTAssertEqual(sample(tasksToday: -1).status(at: now), .invalid)
    }

    func testFreshnessBoundaryAndFutureTimestamp() {
        XCTAssertEqual(sample(updatedAt: now.addingTimeInterval(-86_400)).status(at: now), .ready)
        XCTAssertEqual(sample(updatedAt: now.addingTimeInterval(-86_401)).status(at: now), .stale)
        XCTAssertEqual(sample(updatedAt: now.addingTimeInterval(301)).status(at: now), .invalid)
    }

    func testMissingMalformedStaleAndAtomicRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("grok-usage.json")
        XCTAssertEqual(GrokUsageFile.read(from: file, now: now).status, .missing)
        try GrokUsageFile.write(sample(), to: file, now: now)
        let result = GrokUsageFile.read(from: file, now: now)
        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.snapshot, sample())
        XCTAssertEqual(GrokUsageFile.read(from: file, now: now.addingTimeInterval(86_401)).status, .stale)
        try Data("malformed".utf8).write(to: file)
        XCTAssertEqual(GrokUsageFile.read(from: file, now: now).status, .invalid)
        XCTAssertThrowsError(try GrokUsageFile.write(sample(101), to: file, now: now))
    }

    func testThresholdsAreIndependentPersistedAndCoalescible() throws {
        var codex = DailyUsageTracker()
        var grok = DailyUsageTracker()
        XCTAssertEqual(codex.record(usedPercent: 18, resetAt: reset, at: now, calendar: calendar), [])
        XCTAssertEqual(grok.record(usedPercent: 18, resetAt: reset, at: now, calendar: calendar), [])
        XCTAssertEqual(codex.record(usedPercent: 23, resetAt: reset, at: now, calendar: calendar), [5])
        XCTAssertEqual(grok.record(usedPercent: 38, resetAt: reset, at: now, calendar: calendar), [5, 10, 15, 20])
        var restored = try JSONDecoder().decode(DailyUsageTracker.self, from: JSONEncoder().encode(grok))
        XCTAssertEqual(restored.record(usedPercent: 39, resetAt: reset, at: now, calendar: calendar), [])
        XCTAssertEqual(codex.notifiedThresholds, [5])
        XCTAssertEqual(restored.increase, 21)
    }

    func testCycleResetDoesNotRearmSameDayThresholds() {
        var state = DailyUsageTracker()
        state.record(usedPercent: 80, resetAt: reset, at: now, calendar: calendar)
        XCTAssertEqual(state.record(usedPercent: 90, resetAt: reset, at: now, calendar: calendar), [5, 10])
        let nextReset = reset.addingTimeInterval(86_400 * 7)
        XCTAssertEqual(state.record(usedPercent: 1, resetAt: nextReset, at: now, calendar: calendar), [])
        XCTAssertEqual(state.increase, 0)
        XCTAssertEqual(state.record(usedPercent: 11, resetAt: nextReset, at: now, calendar: calendar), [])
        XCTAssertEqual(state.record(usedPercent: 16, resetAt: nextReset, at: now, calendar: calendar), [15])
    }

    func testNewLocalDayRearmsThresholdsAndStartsNewBaseline() {
        var state = DailyUsageTracker()
        state.record(usedPercent: 10, resetAt: reset, at: now, calendar: calendar)
        state.record(usedPercent: 20, resetAt: reset, at: now, calendar: calendar)
        let tomorrow = now.addingTimeInterval(86_400)
        XCTAssertEqual(state.record(usedPercent: 25, resetAt: reset, at: tomorrow, calendar: calendar), [])
        XCTAssertEqual(state.increase, 0)
        XCTAssertEqual(state.record(usedPercent: 30, resetAt: reset, at: tomorrow, calendar: calendar), [5])
    }

    func testLegacyCodexStateMigrationPreservesBaselineAndNotificationDeduplication() {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let day = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        var state = DailyUsageTracker(day: day, baseline: 10, notifiedThresholds: [5])
        XCTAssertEqual(state.record(usedPercent: 20, resetAt: reset, at: now, calendar: calendar), [10])
        XCTAssertEqual(state.increase, 10)
    }

    func testMenuMaximumExcludesDisabledMissingAndInvalidValues() {
        XCTAssertEqual(UsageAggregation.maximum(codex: 20, codexEnabled: true, grok: 40, grokEnabled: true), 40)
        XCTAssertEqual(UsageAggregation.maximum(codex: 20, codexEnabled: true, grok: 40, grokEnabled: false), 20)
        XCTAssertEqual(UsageAggregation.maximum(codex: nil, codexEnabled: true, grok: 40, grokEnabled: true), 40)
        XCTAssertNil(UsageAggregation.maximum(codex: 20, codexEnabled: false, grok: nil, grokEnabled: true))
        XCTAssertNil(UsageAggregation.maximum(codex: .nan, codexEnabled: true, grok: 101, grokEnabled: true))
    }
}
