import AppKit
import Foundation
import ServiceManagement
import UserNotifications
import UsageCore

enum RefreshSchedule: String, CaseIterable, Identifiable {
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case hourly
    case daily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveMinutes: return "每 5 分钟"
        case .fifteenMinutes: return "每 15 分钟"
        case .thirtyMinutes: return "每 30 分钟"
        case .hourly: return "每 1 小时"
        case .daily: return "每天固定时间"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .fiveMinutes: return 5 * 60
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .hourly: return 60 * 60
        case .daily: return nil
        }
    }
}

@MainActor
final class UsageMonitor: ObservableObject {
    static let shared = UsageMonitor()

    @Published var snapshot: UsageSnapshot?
    @Published var tokenUsage: AccountTokenUsage?
    @Published var tokenUsageErrorMessage: String?
    @Published var dailyIncrease: Double = 0
    @Published var errorMessage: String?
    @Published var isRefreshing = false
    @Published var notificationStatus = "未测试"
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var refreshSchedule: RefreshSchedule
    @Published private(set) var dailyRefreshTime: Date
    @Published private(set) var tokenUnitStyle: TokenUnitStyle

    @Published private(set) var codexMonitoringEnabled: Bool
    @Published private(set) var grokMonitoringEnabled: Bool
    @Published private(set) var grokSnapshot: GrokUsageSnapshot?
    @Published private(set) var grokStatus: GrokUsageStatus = .missing
    @Published private(set) var grokDailyIncrease: Double = 0
    @Published private(set) var grokErrorMessage: String?

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var grokTimer: Timer?
    private var codexTracker = DailyUsageTracker()
    private var grokTracker = DailyUsageTracker()

    init() {
        let defaults = UserDefaults.standard
        codexMonitoringEnabled = defaults.object(forKey: "codexMonitoringEnabled") as? Bool ?? true
        grokMonitoringEnabled = defaults.object(forKey: "grokMonitoringEnabled") as? Bool ?? true
        if let data = defaults.data(forKey: "codexDailyTracker"),
           let saved = try? JSONDecoder().decode(DailyUsageTracker.self, from: data) {
            codexTracker = saved
        } else if let day = defaults.string(forKey: "baselineDay"),
                  let baseline = defaults.object(forKey: "baselineUsedPercent") as? Double {
            codexTracker = DailyUsageTracker(day: day, baseline: baseline,
                notifiedThresholds: Set(defaults.array(forKey: "notifiedThresholds") as? [Int] ?? []))
        }
        if let data = defaults.data(forKey: "grokDailyTracker"),
           let saved = try? JSONDecoder().decode(DailyUsageTracker.self, from: data) { grokTracker = saved }
        refreshSchedule = RefreshSchedule(
            rawValue: defaults.string(forKey: "refreshSchedule") ?? ""
        ) ?? .fifteenMinutes

        let savedMinutes = defaults.object(forKey: "dailyRefreshMinutes") as? Int ?? 9 * 60
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = savedMinutes / 60
        components.minute = savedMinutes % 60
        dailyRefreshTime = Calendar.current.date(from: components) ?? Date()
        tokenUnitStyle = TokenUnitStyle(
            rawValue: defaults.string(forKey: "tokenUnitStyle") ?? ""
        ) ?? .chinese

        requestNotificationPermission()
        refresh()
        scheduleNextRefresh()
        // Check local file freshness even with a daily Codex schedule.
        grokTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshGrok() }
        }
    }

    var codexDataAvailable: Bool {
        guard let snapshot else { return false }
        return codexMonitoringEnabled && errorMessage == nil
            && Date().timeIntervalSince(snapshot.fetchedAt) <= 86_400
    }

    var maximumUsedPercent: Double? {
        UsageAggregation.maximum(codex: codexDataAvailable ? snapshot?.usedPercent : nil,
                                 codexEnabled: codexMonitoringEnabled,
                                 grok: grokStatus == .ready ? grokSnapshot?.usedPercent : nil,
                                 grokEnabled: grokMonitoringEnabled)
    }

    var grokLevel: UsageAlertLevel { DailyUsagePolicy.level(for: grokDailyIncrease) }
    var overallLevel: UsageAlertLevel {
        max(codexDataAvailable ? level : .normal,
            grokMonitoringEnabled && grokStatus == .ready ? grokLevel : .normal)
    }
    var overallStatus: String {
        if !codexMonitoringEnabled && !grokMonitoringEnabled { return "监控已关闭" }
        if overallLevel != .normal { return overallLevel.title }
        if codexMonitoringEnabled && !codexDataAvailable { return "口袋待更新" }
        if grokMonitoringEnabled && grokStatus != .ready { return "Grok Bot \(grokStatus.title)" }
        return "一切正常"
    }

    var menuTitle: String {
        guard let value = maximumUsedPercent else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    var level: UsageAlertLevel {
        DailyUsagePolicy.level(for: dailyIncrease)
    }

    var refreshSummary: String {
        if refreshSchedule == .daily {
            return "每天 \(dailyRefreshTime.formatted(.dateTime.hour().minute())) 更新"
        }
        return "\(refreshSchedule.title)更新"
    }

    func setRefreshSchedule(_ schedule: RefreshSchedule) {
        refreshSchedule = schedule
        defaults.set(schedule.rawValue, forKey: "refreshSchedule")
        scheduleNextRefresh()
    }

    func setDailyRefreshTime(_ date: Date) {
        dailyRefreshTime = date
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 9) * 60 + (components.minute ?? 0)
        defaults.set(minutes, forKey: "dailyRefreshMinutes")
        if refreshSchedule == .daily {
            scheduleNextRefresh()
        }
    }

    func setTokenUnitStyle(_ style: TokenUnitStyle) {
        tokenUnitStyle = style
        defaults.set(style.rawValue, forKey: "tokenUnitStyle")
    }

    func applySettings(
        refreshSchedule schedule: RefreshSchedule,
        dailyRefreshTime date: Date,
        tokenUnitStyle style: TokenUnitStyle
    ) {
        refreshSchedule = schedule
        dailyRefreshTime = date
        tokenUnitStyle = style

        defaults.set(schedule.rawValue, forKey: "refreshSchedule")
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 9) * 60 + (components.minute ?? 0)
        defaults.set(minutes, forKey: "dailyRefreshMinutes")
        defaults.set(style.rawValue, forKey: "tokenUnitStyle")
        scheduleNextRefresh()
    }

    func setMonitoring(codex: Bool, grok: Bool) {
        codexMonitoringEnabled = codex
        grokMonitoringEnabled = grok
        defaults.set(codex, forKey: "codexMonitoringEnabled")
        defaults.set(grok, forKey: "grokMonitoringEnabled")
        if !codex { errorMessage = nil }
        refresh()
    }

    func saveManualGrokUsage(percent: Double, resetAt: Date? = nil) throws {
        guard percent.isFinite, (0...100).contains(percent) else { throw GrokUsageError.invalidData }
        guard let resetAt = resetAt ?? grokSnapshot?.resetAt else { throw GrokUsageError.missingResetDate }
        let previous = grokSnapshot
        let manual = GrokUsageSnapshot(usedPercent: percent, resetAt: resetAt,
            plan: previous?.plan ?? "手动录入", tasksToday: previous?.tasksToday ?? 0,
            tasksPeriod: previous?.tasksPeriod ?? 0)
        try GrokUsageFile.write(manual)
        refreshGrok()
    }

    func refreshGrok() {
        guard grokMonitoringEnabled else {
            grokStatus = .disabled
            grokErrorMessage = nil
            grokDailyIncrease = 0
            return
        }
        let result = GrokUsageFile.read()
        grokSnapshot = result.snapshot
        grokStatus = result.status
        grokErrorMessage = result.message
        guard result.status == .ready, let value = result.snapshot else {
            grokDailyIncrease = 0
            return
        }
        let crossed = grokTracker.record(usedPercent: value.usedPercent, resetAt: value.resetAt)
        grokDailyIncrease = grokTracker.increase
        defaults.set(try? JSONEncoder().encode(grokTracker), forKey: "grokDailyTracker")
        notify(service: "grok-bot", name: "Grok Bot", increase: grokDailyIncrease,
               usedPercent: value.usedPercent, crossed: crossed)
    }

    func refresh() {
        refreshGrok()
        guard codexMonitoringEnabled, !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try CodexAppServerClient().fetchDashboardSnapshot() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRefreshing = false
                guard self.codexMonitoringEnabled else { return }
                switch result {
                case .success(let dashboard):
                    self.accept(dashboard.quota)
                    if let tokenUsage = dashboard.tokenUsage {
                        self.tokenUsage = tokenUsage
                    }
                    self.tokenUsageErrorMessage = dashboard.tokenUsageError
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func sendTestNotification() {
        sendNotification(
            identifier: "codex-usage-test-\(UUID().uuidString)",
            title: "Codex 用量预警测试",
            body: "系统通知工作正常。达到 5%、10%、15% 或 20% 的当日增量时会提醒你。"
        )
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            errorMessage = "无法更新开机启动设置：\(error.localizedDescription)"
        }
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    private func scheduleNextRefresh() {
        timer?.invalidate()

        if let interval = refreshSchedule.interval {
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            return
        }

        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: dailyRefreshTime)
        guard let nextDate = calendar.nextDate(
            after: Date(),
            matching: time,
            matchingPolicy: .nextTime
        ) else { return }

        timer = Timer.scheduledTimer(
            withTimeInterval: max(1, nextDate.timeIntervalSinceNow),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.scheduleNextRefresh()
            }
        }
    }

    private func accept(_ newSnapshot: UsageSnapshot) {
        snapshot = newSnapshot
        let crossed = codexTracker.record(usedPercent: newSnapshot.usedPercent,
                                          resetAt: newSnapshot.resetsAt, at: newSnapshot.fetchedAt)
        dailyIncrease = codexTracker.increase
        defaults.set(try? JSONEncoder().encode(codexTracker), forKey: "codexDailyTracker")
        notify(service: "codex", name: "口袋", increase: dailyIncrease,
               usedPercent: newSnapshot.usedPercent, crossed: crossed)
    }

    private func notify(service: String, name: String, increase: Double,
                        usedPercent: Double, crossed: [Int]) {
        // Coalesce levels crossed in one refresh; all remain consumed today.
        guard let highest = crossed.max() else { return }
        sendNotification(
            identifier: "\(service)-daily-\(Self.dayKey(for: Date()))-\(highest)",
            title: "\(name) · \(DailyUsagePolicy.level(for: increase).title)",
            body: "今天已消耗 \(Self.percent(increase)) 个额度百分点；当前周期累计使用 \(Self.percent(usedPercent))%。"
        )
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                if let error {
                    self?.notificationStatus = error.localizedDescription
                } else {
                    self?.notificationStatus = granted ? "已允许" : "未允许"
                }
            }
        }
    }

    private func sendNotification(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            DispatchQueue.main.async {
                self?.notificationStatus = error?.localizedDescription ?? "已发送"
            }
        }
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
