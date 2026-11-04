import XCTest
@testable import UsageCore

final class MenuBarUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func service(_ percent: Double? = 42.8, enabled: Bool = true,
                         age: TimeInterval = 0, reason: String? = nil) -> MenuBarServiceUsage {
        MenuBarServiceUsage(name: "Codex", label: "C", enabled: enabled,
            usedPercent: percent, updatedAt: now.addingTimeInterval(-age),
            unavailableReason: reason, now: now)
    }

    func testDefaultAndSavedModes() {
        XCTAssertEqual(MenuBarDisplayStyle(savedValue: nil), .progressBars)
        XCTAssertEqual(MenuBarDisplayStyle(savedValue: "unknown"), .progressBars)
        XCTAssertEqual(MenuBarDisplayStyle(savedValue: "numbers"), .numbers)
        XCTAssertEqual(MenuBarDisplayStyle(savedValue: "highest"), .highest)
    }

    func testUsedRemainingAndFillAgree() {
        XCTAssertEqual(service().fraction, 0.428, accuracy: 0.00001)
        XCTAssertEqual(service().number, "43%")
        XCTAssertEqual(service().summary, "Codex：已用 42.8% · 剩余 57.2%")
        XCTAssertEqual(service(0).fraction, 0)
        XCTAssertEqual(service(100).fraction, 1)
        XCTAssertNotNil(service(0).usedPercent)
    }

    func testDisabledAndFailedDataNeverShowOldPercent() {
        XCTAssertNil(service(enabled: false).usedPercent)
        XCTAssertEqual(service(enabled: false).summary, "Codex：监控已关闭")
        XCTAssertEqual(service(reason: "读取失败").number, "—")
        XCTAssertEqual(service(reason: "读取失败").fraction, 0)
    }

    func testFreshnessBoundaryAndInvalidNumbers() {
        XCTAssertNotNil(service(age: 86_400).usedPercent)
        XCTAssertNil(service(age: 86_401).usedPercent)
        XCTAssertEqual(service(age: 86_401).summary, "Codex：数据过期")
        for value: Double? in [nil, -1, 101, .nan, .infinity] {
            XCTAssertNil(service(value).usedPercent)
        }
        let missingDate = MenuBarServiceUsage(name: "Grok Bot", label: "G", enabled: true,
            usedPercent: 20, updatedAt: nil, now: now)
        XCTAssertNil(missingDate.usedPercent)
    }
}
