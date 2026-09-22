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
    @Published private(set) var isLaunchingCodex = false
    @Published var notificationStatus = "unknown"
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var codexSelectionName: String?
    @Published private(set) var codexHomeSelectionName: String?
    @Published private(set) var shouldOfferCodexSelection = false
    @Published private(set) var refreshSchedule: RefreshSchedule
    @Published private(set) var dailyRefreshTime: Date
    @Published private(set) var tokenUnitStyle: TokenUnitStyle

    private let defaults = UserDefaults.standard
    private let codexAccessStore = CodexAccessStore()
    private var codexGrant: CodexExecutableGrant?
    private var codexHomeGrant: CodexHomeGrant?
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
        codexHomeGrant = codexAccessStore.loadCodexHomeGrant()
        codexSelectionName = codexGrant?.displayName
        codexHomeSelectionName = codexHomeGrant?.displayName
        shouldOfferCodexSelection = Self.isRunningInAppSandbox
            && (codexGrant == nil || codexHomeGrant == nil)

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
            return L(
                "每天 \(AppLocalization.shared.time(dailyRefreshTime)) 更新",
                "Daily at \(AppLocalization.shared.time(dailyRefreshTime))"
            )
        }
        return AppLocalization.shared.refreshScheduleTitle(refreshSchedule)
    }

    var codexSourceSummary: String {
        codexSelectionName ?? L("自动查找本机 Codex", "Find Codex automatically")
    }

    var codexHomeSourceSummary: String {
        codexHomeSelectionName ?? L(
            "尚未授权 Codex 登录资料",
            "Codex sign-in data not authorized"
        )
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
        let homeGrant = codexHomeGrant

        DispatchQueue.global(qos: .utility).async {
            let result = Result {
                try CodexAppServerClient(
                    executableURL: grant?.executableURL,
                    securityScopedResourceURL: grant?.selectedURL,
                    codexHomeURL: homeGrant?.selectedURL
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
                    self.errorMessage = self.localizedErrorMessage(error)
                    if Self.isRunningInAppSandbox || Self.isExecutableNotFound(error) {
                        self.shouldOfferCodexSelection = true
                    }
                }
            }
        }
    }

    var canOpenCodexApplication: Bool {
        Self.codexApplicationURL != nil
    }

    func openCodexApplication() {
        guard let applicationURL = Self.codexApplicationURL else {
            errorMessage = L(
                "未找到 Codex/ChatGPT 应用。请先安装并登录，然后重新刷新。",
                "Codex/ChatGPT was not found. Install and sign in, then refresh again."
            )
            return
        }

        isLaunchingCodex = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        ) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.isLaunchingCodex = false
                    self.errorMessage = L(
                        "无法打开 Codex/ChatGPT：\(error.localizedDescription)",
                        "Could not open Codex/ChatGPT: \(error.localizedDescription)"
                    )
                    return
                }

                self.errorMessage = L(
                    "Codex/ChatGPT 已启动，正在等待登录状态就绪…",
                    "Codex/ChatGPT is open. Waiting for sign-in to become ready…"
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    guard let self else { return }
                    self.isLaunchingCodex = false
                    self.refresh()
                }
            }
        }
    }

    func chooseCodexLocation() {
        do {
            guard let grant = try codexAccessStore.chooseGrant() else { return }
            codexGrant = grant
            codexSelectionName = grant.displayName
            shouldOfferCodexSelection = Self.isRunningInAppSandbox && codexHomeGrant == nil
            refresh()
        } catch {
            errorMessage = localizedErrorMessage(error)
            shouldOfferCodexSelection = true
        }
    }

    func chooseCodexHomeLocation() {
        do {
            guard let grant = try codexAccessStore.chooseCodexHomeGrant() else { return }
            codexHomeGrant = grant
            codexHomeSelectionName = grant.displayName
            shouldOfferCodexSelection = Self.isRunningInAppSandbox && codexGrant == nil
            refresh()
        } catch {
            errorMessage = localizedErrorMessage(error)
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

    func clearCodexHomeLocation() {
        codexAccessStore.clearCodexHomeGrant()
        codexHomeGrant = nil
        codexHomeSelectionName = nil
        shouldOfferCodexSelection = Self.isRunningInAppSandbox
        refresh()
    }

    func sendTestNotification() {
        sendNotification(
            identifier: "codex-usage-test-\(UUID().uuidString)",
            title: L("Codex 用量预警测试", "Codex Usage Alert Test"),
            body: L(
                "系统通知工作正常。达到 5%、10%、15% 或 20% 的当日增量时会提醒你。",
                "Notifications are working. You will be alerted at 5%, 10%, 15%, and the daily cap."
            )
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
            errorMessage = L(
                "无法更新开机启动设置：\(error.localizedDescription)",
                "Could not update the launch-at-login setting: \(error.localizedDescription)"
            )
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
        let cachedBudget: DailyBudgetRollover?
        if defaults.string(forKey: "rolloverBudgetDay") == today,
           defaults.integer(forKey: "rolloverBudgetSchemaVersion") == schemaVersion {
            cachedBudget = RolloverBudgetCalculator.calculate(
                windowDurationMins: snapshot.windowDurationMins,
                yesterdayUsedPercent: defaults.object(forKey: "rolloverYesterdayUsed") as? Double,
                sourceDay: defaults.string(forKey: "rolloverSourceDay"),
                yesterdayUsageSource: defaults.string(forKey: "rolloverUsageSource")
                    .flatMap { RolloverUsageSource(rawValue: $0) }
            )
        } else {
            cachedBudget = nil
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
        let canDeriveYesterdayDataNow = hasRecordedYesterday || canUseWindowBaselineEstimate

        if let cachedBudget,
           RolloverBudgetCachePolicy.shouldReuseCachedBudget(
               cachedHasYesterdayData: cachedBudget.hasYesterdayData,
               canDeriveYesterdayDataNow: canDeriveYesterdayDataNow
           ) {
            return cachedBudget
        }

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
            title: AppLocalization.shared.alertLevelTitle(level),
            body: L(
                "今天已消耗 \(Self.percent(dailyIncrease)) 个额度百分点，今日上限 \(Self.percent(dailyCap))%；当前周期累计使用 \(Self.percent(snapshot?.usedPercent ?? 0))%。",
                "Today you used \(Self.percent(dailyIncrease)) percentage points of a \(Self.percent(dailyCap))% cap. Current window usage is \(Self.percent(snapshot?.usedPercent ?? 0))%."
            )
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
                    self?.notificationStatus = granted ? "allowed" : "denied"
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
                self?.notificationStatus = error?.localizedDescription ?? "sent"
            }
        }
    }

    private func localizedErrorMessage(_ error: Error) -> String {
        if let error = error as? CodexUsageClientError {
            switch error {
            case .executableNotFound:
                return L(
                    "未找到 Codex CLI。请先安装并登录 Codex。",
                    "Codex CLI was not found. Install and sign in to Codex first."
                )
            case .serverExited:
                return L(
                    "Codex App Server 在返回用量前退出。",
                    "Codex App Server exited before returning usage data."
                )
            case .timedOut:
                return L("读取 Codex 用量超时。", "Timed out while reading Codex usage.")
            case .invalidResponse(let detail):
                return L(
                    "Codex 返回了无法识别的数据：\(detail)",
                    "Codex returned an unrecognized response: \(detail)"
                )
            case .serverError(let detail):
                if detail.localizedCaseInsensitiveContains("failed to fetch codex rate limits") {
                    return L(
                        "Codex 尚未就绪。请先打开 Codex/ChatGPT 并确认已登录，然后返回刷新。",
                        "Codex is not ready. Open Codex/ChatGPT, confirm you are signed in, then refresh."
                    )
                }
                return L("Codex App Server 错误：\(detail)", "Codex App Server error: \(detail)")
            }
        }

        if let error = error as? CodexAccessStoreError {
            switch error {
            case .unsupportedSelection:
                return L(
                    "所选项目中没有找到可执行的 Codex 程序。",
                    "No executable Codex app was found in the selected item."
                )
            case .missingCodexAuthentication:
                return L(
                    "所选文件夹中没有找到 Codex 登录资料（auth.json）。",
                    "Codex sign-in data (auth.json) was not found in the selected folder."
                )
            }
        }

        return error.localizedDescription
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

    private static var codexApplicationURL: URL? {
        let workspace = NSWorkspace.shared
        for bundleIdentifier in ["com.openai.codex", "com.openai.chat"] {
            if let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return url
            }
        }

        for path in ["/Applications/Codex.app", "/Applications/ChatGPT.app"] {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private static func isExecutableNotFound(_ error: Error) -> Bool {
        guard let clientError = error as? CodexUsageClientError else { return false }
        if case .executableNotFound = clientError { return true }
        return false
    }
}
