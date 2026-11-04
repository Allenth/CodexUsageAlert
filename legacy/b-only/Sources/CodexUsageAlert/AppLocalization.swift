import Foundation
import UsageCore

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese
    case english

    var id: String { rawValue }
}

@MainActor
final class AppLocalization: ObservableObject {
    static let shared = AppLocalization()

    @Published private(set) var selection: AppLanguage

    private let defaults = UserDefaults.standard

    private init() {
        selection = AppLanguage(
            rawValue: defaults.string(forKey: "appLanguage") ?? ""
        ) ?? .system
    }

    var isChinese: Bool {
        switch selection {
        case .simplifiedChinese:
            return true
        case .english:
            return false
        case .system:
            return Locale.preferredLanguages.first?
                .lowercased()
                .hasPrefix("zh") == true
        }
    }

    var locale: Locale {
        Locale(identifier: isChinese ? "zh_Hans_CN" : "en_US")
    }

    func setLanguage(_ language: AppLanguage) {
        selection = language
        defaults.set(language.rawValue, forKey: "appLanguage")
    }

    func text(_ chinese: String, _ english: String) -> String {
        isChinese ? chinese : english
    }

    func languageTitle(_ language: AppLanguage) -> String {
        switch language {
        case .system: return text("跟随系统", "System")
        case .simplifiedChinese: return text("简体中文", "Simplified Chinese")
        case .english: return "English"
        }
    }

    func refreshScheduleTitle(_ schedule: RefreshSchedule) -> String {
        switch schedule {
        case .fiveMinutes: return text("每 5 分钟", "Every 5 minutes")
        case .fifteenMinutes: return text("每 15 分钟", "Every 15 minutes")
        case .thirtyMinutes: return text("每 30 分钟", "Every 30 minutes")
        case .hourly: return text("每 1 小时", "Every hour")
        case .daily: return text("每天固定时间", "Once daily")
        }
    }

    func tokenUnitTitle(_ style: TokenUnitStyle) -> String {
        switch style {
        case .chinese: return text("中文（万 / 亿）", "Chinese (10K / 100M)")
        case .english: return "English (K / M / B)"
        }
    }

    func alertLevelTitle(_ level: UsageAlertLevel) -> String {
        switch level {
        case .normal: return text("正常", "Normal")
        case .notice: return text("用量提醒", "Usage notice")
        case .reminder: return text("用量偏高", "High usage")
        case .high: return text("接近每日上限", "Near daily cap")
        case .cap: return text("达到每日上限", "Daily cap reached")
        }
    }

    func date(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale)
                .month()
                .day()
        )
    }

    func time(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
                .hour()
                .minute()
        )
    }
}

@MainActor
func L(_ chinese: String, _ english: String) -> String {
    AppLocalization.shared.text(chinese, english)
}
