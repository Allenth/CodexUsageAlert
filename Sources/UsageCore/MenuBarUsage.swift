import Foundation

public enum MenuBarDisplayStyle: String, CaseIterable, Identifiable {
    case progressBars, numbers, highest

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .progressBars: return "显示两条进度条"
        case .numbers: return "只显示数字"
        case .highest: return "只显示最高值"
        }
    }

    public init(savedValue: String?) {
        self = savedValue.flatMap(Self.init(rawValue:)) ?? .progressBars
    }
}

/// Shared presentation rules keep stale/disabled readings out of every menu mode.
public struct MenuBarServiceUsage: Equatable {
    public let name: String
    public let label: String
    public let usedPercent: Double?
    public let status: String

    public init(name: String, label: String, enabled: Bool, usedPercent: Double?,
                updatedAt: Date?, unavailableReason: String? = nil, now: Date = Date()) {
        self.name = name
        self.label = label
        if !enabled {
            self.usedPercent = nil
            status = "监控已关闭"
        } else if let unavailableReason {
            self.usedPercent = nil
            status = unavailableReason
        } else if let updatedAt, now.timeIntervalSince(updatedAt) > 86_400 {
            self.usedPercent = nil
            status = "数据过期"
        } else if let usedPercent, usedPercent.isFinite, (0...100).contains(usedPercent), updatedAt != nil {
            self.usedPercent = usedPercent
            status = "已更新"
        } else {
            self.usedPercent = nil
            status = "等待有效数据"
        }
    }

    public var fraction: Double { (usedPercent ?? 0) / 100 }
    public var number: String { usedPercent.map { "\(Int($0.rounded()))%" } ?? "—" }
    public var summary: String {
        guard let usedPercent else { return "\(name)：\(status)" }
        return "\(name)：已用 \(Self.percent(usedPercent))% · 剩余 \(Self.percent(100 - usedPercent))%"
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
