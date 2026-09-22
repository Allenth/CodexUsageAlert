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

    private let defaults = UserDefaults.standard
    private var timer: Timer?

    init() {
        let defaults = UserDefaults.standard
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
    }

    var menuTitle: String {
        guard let snapshot else { return "…" }
        return "\(Int(snapshot.usedPercent.rounded()))%"
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

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil

        DispatchQueue.global(qos: .utility).async {
            let result = Result { try CodexAppServerClient().fetchDashboardSnapshot() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRefreshing = false
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

        let today = Self.dayKey(for: newSnapshot.fetchedAt)
        let savedDay = defaults.string(forKey: "baselineDay")
        let savedBaseline = defaults.object(forKey: "baselineUsedPercent") as? Double

        if savedDay != today || savedBaseline == nil || newSnapshot.usedPercent < (savedBaseline ?? 0) {
            defaults.set(today, forKey: "baselineDay")
            defaults.set(newSnapshot.usedPercent, forKey: "baselineUsedPercent")
            defaults.set([], forKey: "notifiedThresholds")
            dailyIncrease = 0
            return
        }

        let baseline = savedBaseline ?? newSnapshot.usedPercent
        dailyIncrease = DailyUsagePolicy.increase(
            baseline: baseline,
            current: newSnapshot.usedPercent
        )
        notifyForCrossedThresholds()
    }

    private func notifyForCrossedThresholds() {
        var notified = Set(defaults.array(forKey: "notifiedThresholds") as? [Int] ?? [])
        let crossed = DailyUsagePolicy.defaultThresholds
            .map(Int.init)
            .filter { dailyIncrease >= Double($0) && !notified.contains($0) }

        guard let highest = crossed.max() else { return }
        notified.formUnion(crossed)
        defaults.set(Array(notified).sorted(), forKey: "notifiedThresholds")

        let level = DailyUsagePolicy.level(for: dailyIncrease)
        sendNotification(
            identifier: "codex-daily-\(Self.dayKey(for: Date()))-\(highest)",
            title: level.title,
            body: "今天已消耗 \(Self.percent(dailyIncrease)) 个额度百分点；当前周期累计使用 \(Self.percent(snapshot?.usedPercent ?? 0))%。"
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
