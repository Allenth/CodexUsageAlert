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
    @Published var rolloverBudget: DailyBudgetRollover?
    @Published var errorMessage: String?
    @Published var isRefreshing = false
    @Published var notificationStatus = "未测试"
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var codexSelectionName: String?
    @Published private(set) var shouldOfferCodexSelection = false
    @Published private(set) var refreshSchedule: RefreshSchedule
    @Published private(set) var dailyRefreshTime: Date
    @Published private(set) var tokenUnitStyle: TokenUnitStyle

    private let defaults = UserDefaults.standard
    private let codexAccessStore = CodexAccessStore()
    private var codexGrant: CodexExecutableGrant?
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
        codexGrant = codexAccessStore.loadGrant()
        codexSelectionName = codexGrant?.displayName
        shouldOfferCodexSelection = Self.isRunningInAppSandbox && codexGrant == nil

        requestNotificationPermission()
        refresh()
        scheduleNextRefresh()
    }

    var menuTitle: String {
        guard let snapshot else { return "…" }
        return "\(Int(snapshot.usedPercent.rounded()))%"
    }

    var level: UsageAlertLevel {
        DailyUsagePolicy.level(
            for: dailyIncrease,
            dailyCap: rolloverBudget?.todayAvailablePercent ?? 20
        )
    }

    var refreshSummary: String {
        if refreshSchedule == .daily {
            return "每天 \(dailyRefreshTime.formatted(.dateTime.hour().minute())) 更新"
        }
        return "\(refreshSchedule.title)更新"
    }

    var codexSourceSummary: String {
        codexSelectionName ?? "自动查找本机 Codex"
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
        let grant = codexGrant

        DispatchQueue.global(qos: .utility).async {
            let result = Result {
                try CodexAppServerClient(
                    executableURL: grant?.executableURL,
                    securityScopedResourceURL: grant?.selectedURL
                ).fetchDashboardSnapshot()
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRefreshing = false
                switch result {
                case .success(let dashboard):
                    self.shouldOfferCodexSelection = false
                    self.accept(dashboard.quota)
                    if let tokenUsage = dashboard.tokenUsage {
                        self.tokenUsage = tokenUsage
                    }
                    self.tokenUsageErrorMessage = dashboard.tokenUsageError
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    if Self.isRunningInAppSandbox || Self.isExecutableNotFound(error) {
                        self.shouldOfferCodexSelection = true
                    }
                }
            }
        }
    }

    func chooseCodexLocation() {
        do {
            guard let grant = try codexAccessStore.chooseGrant() else { return }
            codexGrant = grant
            codexSelectionName = grant.displayName
            shouldOfferCodexSelection = false
            refresh()
        } catch {
            errorMessage = error.localizedDescription
            shouldOfferCodexSelection = true
        }
    }

    func clearCodexLocation() {
        codexAccessStore.clearGrant()
        codexGrant = nil
        codexSelectionName = nil
        shouldOfferCodexSelection = Self.isRunningInAppSandbox
        refresh()
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
        let budget = prepareRolloverBudget(
            for: today,
            snapshot: newSnapshot,
            previousBaselineDay: savedDay,
            previousBaselinePercent: savedBaseline
        )
        rolloverBudget = budget

        if savedDay != today || savedBaseline == nil {
            defaults.set(today, forKey: "baselineDay")
            defaults.set(newSnapshot.usedPercent, forKey: "baselineUsedPercent")
            defaults.set(0.0, forKey: "dailyUsageOffset")
            defaults.set([], forKey: "notifiedThresholds")
            defaults.set([], forKey: "notifiedThresholdKeys")
            dailyIncrease = 0
            saveDailyUsage(0, for: today)
            return
        }

        guard let baseline = savedBaseline else { return }

        if newSnapshot.usedPercent < baseline {
            let recorded = recordedDailyUsage(for: today) ?? dailyIncrease
            defaults.set(newSnapshot.usedPercent, forKey: "baselineUsedPercent")
            defaults.set(recorded, forKey: "dailyUsageOffset")
            dailyIncrease = recorded
            saveDailyUsage(recorded, for: today)
            return
        }

        let offset = defaults.object(forKey: "dailyUsageOffset") as? Double ?? 0
        dailyIncrease = offset + DailyUsagePolicy.increase(
            baseline: baseline,
            current: newSnapshot.usedPercent
        )
        saveDailyUsage(dailyIncrease, for: today)
        notifyForCrossedThresholds()
    }

    private func prepareRolloverBudget(
        for today: String,
        snapshot: UsageSnapshot,
        previousBaselineDay: String?,
        previousBaselinePercent: Double?
    ) -> DailyBudgetRollover {
        let schemaVersion = 3
        if defaults.string(forKey: "rolloverBudgetDay") == today,
           defaults.integer(forKey: "rolloverBudgetSchemaVersion") == schemaVersion {
            return RolloverBudgetCalculator.calculate(
                windowDurationMins: snapshot.windowDurationMins,
                yesterdayUsedPercent: defaults.object(forKey: "rolloverYesterdayUsed") as? Double,
                sourceDay: defaults.string(forKey: "rolloverSourceDay"),
                yesterdayUsageSource: defaults.string(forKey: "rolloverUsageSource")
                    .flatMap { RolloverUsageSource(rawValue: $0) }
            )
        }

        let previousDate = Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: snapshot.fetchedAt
        )
        let previousDay = previousDate.map(Self.dayKey(for:))
        let usageDay = defaults.string(forKey: "dailyUsageRecordDay")
        let hasRecordedYesterday = previousDay != nil
            && previousBaselineDay == previousDay
            && usageDay == previousDay

        let windowStartedAt = snapshot.resetsAt.addingTimeInterval(
            -snapshot.windowDurationMins * 60
        )
        let windowStartedYesterday = previousDay != nil
            && Self.dayKey(for: windowStartedAt) == previousDay
        let canUseWindowBaselineEstimate = previousDay != nil
            && previousBaselineDay == today
            && previousBaselinePercent != nil
            && windowStartedYesterday

        let yesterdayUsed: Double?
        let usageSource: RolloverUsageSource?
        if hasRecordedYesterday {
            yesterdayUsed = defaults.object(forKey: "dailyUsageRecordPercent") as? Double
            usageSource = .localDailySnapshots
        } else if canUseWindowBaselineEstimate {
            yesterdayUsed = previousBaselinePercent
            usageSource = .windowBaselineEstimate
        } else {
            yesterdayUsed = nil
            usageSource = nil
        }
        let budget = RolloverBudgetCalculator.calculate(
            windowDurationMins: snapshot.windowDurationMins,
            yesterdayUsedPercent: yesterdayUsed,
            sourceDay: yesterdayUsed == nil ? nil : previousDay,
            yesterdayUsageSource: usageSource
        )

        defaults.set(today, forKey: "rolloverBudgetDay")
        defaults.set(schemaVersion, forKey: "rolloverBudgetSchemaVersion")
        if let yesterdayUsed {
            defaults.set(yesterdayUsed, forKey: "rolloverYesterdayUsed")
        } else {
            defaults.removeObject(forKey: "rolloverYesterdayUsed")
        }
        if let usageSource {
            defaults.set(usageSource.rawValue, forKey: "rolloverUsageSource")
        } else {
            defaults.removeObject(forKey: "rolloverUsageSource")
        }
        defaults.removeObject(forKey: "rolloverYesterdayAvailable")
        defaults.removeObject(forKey: "availableBudgetDay")
        defaults.removeObject(forKey: "availableBudgetPercent")
        if let previousDay, yesterdayUsed != nil {
            defaults.set(previousDay, forKey: "rolloverSourceDay")
        } else {
            defaults.removeObject(forKey: "rolloverSourceDay")
        }
        return budget
    }

    private func recordedDailyUsage(for day: String) -> Double? {
        guard defaults.string(forKey: "dailyUsageRecordDay") == day else { return nil }
        return defaults.object(forKey: "dailyUsageRecordPercent") as? Double
    }

    private func saveDailyUsage(_ value: Double, for day: String) {
        defaults.set(day, forKey: "dailyUsageRecordDay")
        defaults.set(max(0, value), forKey: "dailyUsageRecordPercent")
    }

    private func notifyForCrossedThresholds() {
        let dailyCap = rolloverBudget?.todayAvailablePercent ?? 20
        var notified = Set(defaults.stringArray(forKey: "notifiedThresholdKeys") ?? [])
        let crossed = DailyUsagePolicy.notificationThresholds(dailyCap: dailyCap)
            .filter { threshold in
                dailyIncrease >= threshold && !notified.contains(thresholdKey(threshold))
            }

        guard let highest = crossed.max() else { return }
        notified.formUnion(crossed.map(thresholdKey))
        defaults.set(Array(notified).sorted(), forKey: "notifiedThresholdKeys")

        let level = DailyUsagePolicy.level(for: dailyIncrease, dailyCap: dailyCap)
        sendNotification(
            identifier: "codex-daily-\(Self.dayKey(for: Date()))-\(thresholdKey(highest))",
            title: level.title,
            body: "今天已消耗 \(Self.percent(dailyIncrease)) 个额度百分点，今日上限 \(Self.percent(dailyCap))%；当前周期累计使用 \(Self.percent(snapshot?.usedPercent ?? 0))%。"
        )
    }

    private func thresholdKey(_ value: Double) -> String {
        String(format: "%.1f", value)
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

    private static var isRunningInAppSandbox: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private static func isExecutableNotFound(_ error: Error) -> Bool {
        guard let clientError = error as? CodexUsageClientError else { return false }
        if case .executableNotFound = clientError { return true }
        return false
    }
}
