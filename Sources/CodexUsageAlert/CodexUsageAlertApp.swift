import AppKit
import SwiftUI
import UsageCore

@main
struct CodexUsageAlertApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = UsageMonitor.shared
    @StateObject private var localization = AppLocalization.shared

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(monitor: monitor)
                .environmentObject(localization)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: MenuBarIcon.image)
                    .frame(width: 18, height: 18)
                Text(monitor.menuTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }

            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setShouldAntialias(true)

            let iconRect = CGRect(x: 0.75, y: 0.75, width: 16.5, height: 16.5)
            let iconPath = CGPath(
                roundedRect: iconRect,
                cornerWidth: 4.2,
                cornerHeight: 4.2,
                transform: nil
            )

            context.saveGState()
            context.addPath(iconPath)
            context.clip()
            if let background = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    NSColor(
                        calibratedRed: 0.06,
                        green: 0.20,
                        blue: 0.48,
                        alpha: 1
                    ).cgColor,
                    NSColor(
                        calibratedRed: 0.015,
                        green: 0.045,
                        blue: 0.15,
                        alpha: 1
                    ).cgColor,
                ] as CFArray,
                locations: [0, 1]
            ) {
                context.drawLinearGradient(
                    background,
                    start: CGPoint(x: 4, y: 17),
                    end: CGPoint(x: 14, y: 1),
                    options: []
                )
            }
            context.restoreGState()

            context.addPath(iconPath)
            context.setStrokeColor(
                NSColor(
                    calibratedRed: 0.12,
                    green: 0.48,
                    blue: 0.92,
                    alpha: 0.8
                ).cgColor
            )
            context.setLineWidth(0.8)
            context.strokePath()

            context.setLineWidth(3.35)
            context.setLineCap(.round)
            context.addArc(
                center: CGPoint(x: 8.4, y: 8.2),
                radius: 5.15,
                startAngle: 35 * .pi / 180,
                endAngle: 322 * .pi / 180,
                clockwise: false
            )
            context.setStrokeColor(
                NSColor(
                    calibratedRed: 0.25,
                    green: 0.40,
                    blue: 0.68,
                    alpha: 1
                ).cgColor
            )
            context.strokePath()

            if let ringGradient = CGGradient(
                   colorsSpace: CGColorSpaceCreateDeviceRGB(),
                   colors: [
                       NSColor(
                           calibratedRed: 0.22,
                           green: 1.00,
                           blue: 0.95,
                           alpha: 1
                       ).cgColor,
                       NSColor(
                           calibratedRed: 0.02,
                           green: 0.58,
                           blue: 1.00,
                           alpha: 1
                       ).cgColor,
                   ] as CFArray,
                   locations: [0, 1]
               ) {
                context.saveGState()
                context.setLineWidth(3.35)
                context.setLineCap(.round)
                context.addArc(
                    center: CGPoint(x: 8.4, y: 8.2),
                    radius: 5.15,
                    startAngle: 70 * .pi / 180,
                    endAngle: 300 * .pi / 180,
                    clockwise: false
                )
                context.replacePathWithStrokedPath()
                context.clip()
                context.drawLinearGradient(
                    ringGradient,
                    start: CGPoint(x: 3, y: 14),
                    end: CGPoint(x: 13, y: 3),
                    options: []
                )
                context.restoreGState()
            }

            context.saveGState()
            context.setShadow(
                offset: .zero,
                blur: 2.3,
                color: NSColor.systemOrange.withAlphaComponent(0.9).cgColor
            )
            context.setFillColor(NSColor.systemYellow.cgColor)
            context.fillEllipse(in: CGRect(x: 12.2, y: 12.0, width: 2.7, height: 2.7))
            context.restoreGState()

            context.setStrokeColor(NSColor.systemYellow.cgColor)
            context.setLineWidth(0.9)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: 13.55, y: 15.2))
            context.addLine(to: CGPoint(x: 13.55, y: 16.1))
            context.move(to: CGPoint(x: 15.25, y: 13.35))
            context.addLine(to: CGPoint(x: 16.1, y: 13.35))
            context.strokePath()
            return true
        }
        image.isTemplate = false
        return image
    }()
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static weak var current: AppDelegate?
    private var dashboardWindow: NSWindow?
    private var allowsCompleteTermination = false
    private let backgroundNoticeKey = "didShowMenuBarBackgroundNotice"

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceWillPowerOff),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
        DispatchQueue.main.async {
            self.showDashboard(NSApplication.shared)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !allowsCompleteTermination else { return .terminateNow }
        showBackgroundNoticeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.enterMenuBarMode(sender)
        }
        return .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === dashboardWindow else { return true }
        showBackgroundNoticeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.enterMenuBarMode(NSApplication.shared)
        }
        return true
    }

    func applicationShouldHandleReopen(
        _ application: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showDashboard(application)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                if url.host == "test-notification" {
                    UsageMonitor.shared.sendTestNotification()
                } else if url.host == "refresh" {
                    UsageMonitor.shared.refresh()
                    self.showDashboard(application)
                } else if url.host == "show" {
                    self.showDashboard(application)
                } else if url.host == "launch-at-login" {
                    let enabled = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?
                        .first(where: { $0.name == "enabled" })?
                        .value != "0"
                    UsageMonitor.shared.setLaunchAtLogin(enabled)
                }
            }
        }
    }

    private func showDashboard(_ application: NSApplication) {
        application.setActivationPolicy(.regular)
        application.activate(ignoringOtherApps: true)
        let window = dashboardWindow ?? makeDashboardWindow()
        dashboardWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func makeDashboardWindow() -> NSWindow {
        let rootView = UsagePopover(monitor: UsageMonitor.shared)
            .environmentObject(AppLocalization.shared)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Codex Usage Alert"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.contentMinSize = NSSize(width: 380, height: 820)
        window.contentMaxSize = NSSize(width: 380, height: 920)
        window.setContentSize(NSSize(width: 380, height: 820))
        window.backgroundColor = NSColor(
            calibratedRed: 0.025,
            green: 0.045,
            blue: 0.10,
            alpha: 1
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.standardWindowButton(.closeButton)?.target = self
        window.standardWindowButton(.closeButton)?.action = #selector(closeDashboard)
        window.setFrameAutosaveName("CodexUsageAlertDashboard")
        window.center()
        return window
    }

    @objc private func closeDashboard() {
        showBackgroundNoticeIfNeeded()
        enterMenuBarMode(NSApplication.shared)
    }

    private func enterMenuBarMode(_ application: NSApplication) {
        for window in application.windows where window.canBecomeKey {
            window.orderOut(nil)
        }
        application.setActivationPolicy(.accessory)
    }

    private func showBackgroundNoticeIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: backgroundNoticeKey) else { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L("应用将在菜单栏继续运行", "The app will keep running in the menu bar")
        alert.informativeText = L(
            "关闭窗口或按 Command + Q 只会隐藏主界面和 Dock 图标，用量监控仍会继续。如需完全退出，请点击菜单栏面板中的电源按钮。",
            "Closing the window or pressing Command-Q hides the dashboard and Dock icon while monitoring continues. To quit completely, use the power button in the menu bar panel."
        )
        alert.addButton(withTitle: L("知道了", "Got it"))
        alert.runModal()
        defaults.set(true, forKey: backgroundNoticeKey)
    }

    @objc private func workspaceWillPowerOff() {
        allowsCompleteTermination = true
    }

    fileprivate static func quitCompletely() {
        current?.allowsCompleteTermination = true
        NSApplication.shared.terminate(nil)
    }
}

private struct UsagePopover: View {
    @ObservedObject var monitor: UsageMonitor
    @EnvironmentObject private var localization: AppLocalization
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.075, blue: 0.16),
                    Color(red: 0.025, green: 0.045, blue: 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.cyan.opacity(0.08))
                .frame(width: 230, height: 230)
                .blur(radius: 55)
                .offset(x: -150, y: -240)

            VStack(spacing: 16) {
                header

                VStack(spacing: 8) {
                    HStack {
                        Text(L("额度概览", "Usage overview"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                        Spacer()
                        InfoPopoverButton(
                            title: L("额度概览说明", "Usage overview"),
                            sections: overviewInfoSections
                        )
                    }

                    HStack(spacing: 24) {
                        UsageGauge(
                            progressPercent: dailyProgressPercent,
                            primaryPercent: monitor.dailyIncrease,
                            label: L("今日已用", "Used today"),
                            secondaryText: L(
                                "今日上限 \(UsageMonitor.percent(todayCap))%",
                                "Daily cap \(UsageMonitor.percent(todayCap))%"
                            ),
                            color: statusColor,
                            isRefreshing: monitor.isRefreshing
                        )

                        VStack(alignment: .leading, spacing: 13) {
                            MetricRow(
                                icon: "gauge.with.dots.needle.33percent",
                                label: L("今日剩余", "Today left"),
                                value: "\(UsageMonitor.percent(todayRemaining))%",
                                tint: statusColor
                            )
                            MetricRow(
                                icon: "chart.pie.fill",
                                label: L("周期已用", "Window used"),
                                value: "\(UsageMonitor.percent(monitor.snapshot?.usedPercent ?? 0))%",
                                tint: .cyan
                            )
                            MetricRow(
                                icon: "chart.pie.fill",
                                label: L("周期剩余", "Window left"),
                                value: "\(UsageMonitor.percent(monitor.snapshot?.remainingPercent ?? 100))%",
                                tint: .cyan
                            )
                        }
                    }
                }

                DailyBudgetCard(
                    dailyIncrease: monitor.dailyIncrease,
                    statusColor: statusColor,
                    budget: monitor.rolloverBudget,
                    thresholds: monitor.alertThresholds
                )

                if let tokenUsage = monitor.tokenUsage {
                    TokenUsageCard(
                        usage: tokenUsage,
                        unitStyle: monitor.tokenUnitStyle
                    )
                } else {
                    TokenUsageUnavailableCard(
                        isRefreshing: monitor.isRefreshing,
                        errorMessage: monitor.tokenUsageErrorMessage
                    )
                }

                if let snapshot = monitor.snapshot {
                    HStack(spacing: 9) {
                        StatTile(
                            icon: "calendar.badge.clock",
                            value: localization.date(snapshot.resetsAt),
                            detail: localization.time(snapshot.resetsAt),
                            label: L("下次重置", "Next reset"),
                            infoTitle: L("下次重置说明", "Next reset"),
                            infoText: L(
                                "日期和时间来自 Codex 服务端返回的额度窗口重置时间，并按本机系统时区显示。",
                                "This date and time come from the Codex usage-window reset timestamp and are displayed in this Mac's system timezone."
                            )
                        )
                        StatTile(
                            icon: "clock.arrow.circlepath",
                            value: L(
                                "\(UsageMonitor.percent(snapshot.windowDays)) 天",
                                "\(UsageMonitor.percent(snapshot.windowDays)) days"
                            ),
                            detail: L("滚动周期", "Rolling window"),
                            label: L("额度周期", "Usage window"),
                            infoTitle: L("额度周期说明", "Usage window"),
                            infoText: L(
                                "额度周期由 Codex 服务端定义。它是滚动窗口，不等同于自然周或每天重新计算。",
                                "The quota window is defined by Codex. It is a rolling window, not a calendar week or a daily reset."
                            )
                        )
                        StatTile(
                            icon: "bell.badge.fill",
                            value: [
                                monitor.alertThresholds.notice,
                                monitor.alertThresholds.reminder,
                                monitor.alertThresholds.high,
                            ].map(UsageMonitor.percent).joined(separator: " · "),
                            detail: L(
                                "\(UsageMonitor.percent(monitor.alertThresholds.baseCap))% 基础上限",
                                "\(UsageMonitor.percent(monitor.alertThresholds.baseCap))% base cap"
                            ),
                            label: L("预警刻度", "Alert levels"),
                            infoTitle: L("预警刻度说明", "Alert levels"),
                            infoText: L(
                                "前三个数值分别是注意、提醒和偏高阈值；基础上限是你的个人每日预算，不是 OpenAI 官方硬限制。可在设置中修改。",
                                "The first three values are Notice, Alert, and High thresholds. The base cap is your personal daily budget, not an official OpenAI hard limit, and can be changed in Settings."
                            )
                        )
                    }
                }

                if let error = monitor.errorMessage {
                    ErrorBanner(
                        message: error,
                        canOpenCodex: monitor.canOpenCodexApplication,
                        isLaunchingCodex: monitor.isLaunchingCodex,
                        onOpenCodex: monitor.openCodexApplication
                    )
                }

                if monitor.shouldOfferCodexSelection {
                    CodexAccessCard(monitor: monitor)
                }

                controls

                footer
            }
            .foregroundStyle(.white)
            .frame(width: 344)
            .padding(18)

            if showingSettings {
                Color.black.opacity(0.48)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { }

                RefreshSettingsView(monitor: monitor) {
                    showingSettings = false
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(width: 380)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.16), value: showingSettings)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .interpolation(.high)
                .frame(width: 42, height: 42)
                .shadow(color: .cyan.opacity(0.2), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(L("Codex 用量预警", "Codex Usage Alert"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(lastUpdatedText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.52))
            }

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: statusColor.opacity(0.75), radius: 4)
                Text(localization.alertLevelTitle(monitor.level))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(statusColor.opacity(0.25), lineWidth: 1))
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    monitor.refresh()
                } label: {
                    HStack(spacing: 7) {
                        if monitor.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(monitor.isRefreshing
                             ? L("正在读取", "Reading…")
                             : L("立即刷新", "Refresh now"))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.00, green: 0.58, blue: 0.72))
                .controlSize(.large)
                .disabled(monitor.isRefreshing)

                Button {
                    monitor.sendTestNotification()
                } label: {
                    Label(L("测试通知", "Test alert"), systemImage: "bell.fill")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.white.opacity(0.12))
                .controlSize(.large)
            }

            HStack {
                Toggle(
                    L("登录时自动启动", "Launch at login"),
                    isOn: Binding(
                        get: { monitor.launchAtLogin },
                        set: { monitor.setLaunchAtLogin($0) }
                    )
                )
                .toggleStyle(.switch)
                .tint(.cyan)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.78))

                Spacer()

                Label(notificationSummary, systemImage: notificationIcon)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.62))
                .help(L("刷新与通知设置", "Refresh, language, and notification settings"))

                Button {
                    AppDelegate.quitCompletely()
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.62))
                .help(L("完全退出应用", "Quit completely"))
            }
            .padding(.horizontal, 3)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text(monitor.refreshSummary)
                .lineLimit(1)
        }
        .font(.system(size: 9.5))
        .foregroundStyle(.white.opacity(0.38))
    }

    private var statusColor: Color {
        switch monitor.level {
        case .normal: return Color(red: 0.15, green: 0.88, blue: 0.78)
        case .notice: return Color(red: 1.00, green: 0.78, blue: 0.22)
        case .reminder: return Color(red: 1.00, green: 0.55, blue: 0.15)
        case .high, .cap: return Color(red: 1.00, green: 0.30, blue: 0.32)
        }
    }

    private var lastUpdatedText: String {
        guard let date = monitor.snapshot?.fetchedAt else {
            return L("正在连接本机 Codex…", "Connecting to local Codex…")
        }
        return L(
            "更新于 \(localization.time(date))",
            "Updated \(localization.time(date))"
        )
    }

    private var notificationSummary: String {
        let normalized = monitor.notificationStatus.lowercased()
        if normalized.contains("not allowed") || normalized.contains("denied") {
            return L("未允许", "Not allowed")
        }
        switch monitor.notificationStatus {
        case "allowed", "sent": return L("已开启", "On")
        case "denied": return L("未允许", "Not allowed")
        case "unknown": return L("未测试", "Not tested")
        default: return monitor.notificationStatus.count > 8
            ? L("需检查", "Check")
            : monitor.notificationStatus
        }
    }

    private var notificationIcon: String {
        monitor.notificationStatus == "denied" ? "bell.slash.fill" : "bell.fill"
    }

    private var overviewInfoSections: [InfoPopoverSection] {
        [
            InfoPopoverSection(
                icon: "gauge.with.dots.needle.33percent",
                title: L("今日已用与剩余", "Used and remaining today"),
                text: L(
                    "今日已用由此电脑保存的当天首次额度记录与当前周期已用量之差计算；今日剩余等于今日上限减去今日已用。换电脑后会从首次刷新重新记录。",
                    "Used today is the difference between the first quota snapshot saved on this Mac today and the current window usage. Today left is today's cap minus that increase. A new Mac starts recording from its first refresh."
                )
            ),
            InfoPopoverSection(
                icon: "chart.pie.fill",
                title: L("周期已用与剩余", "Window used and remaining"),
                text: L(
                    "周期已用、周期剩余和重置时间直接来自 Codex 服务端 account/rateLimits/read。",
                    "Window used, window remaining, and reset time come directly from Codex account/rateLimits/read."
                )
            ),
            InfoPopoverSection(
                icon: "shield.lefthalf.filled",
                title: L("数据与隐私", "Data and privacy"),
                text: L(
                    "应用通过本机 Codex App Server 读取用量，不收集账号密码、Cookie 或 API Key，也不上传用量数据。",
                    "The app reads usage through the local Codex App Server. It does not collect passwords, cookies, or API keys, and does not upload usage data."
                )
            ),
        ]
    }

    private var todayCap: Double {
        monitor.rolloverBudget?.todayAvailablePercent ?? monitor.alertThresholds.baseCap
    }

    private var todayRemaining: Double {
        max(0, todayCap - monitor.dailyIncrease)
    }

    private var dailyProgressPercent: Double {
        guard todayCap > 0 else { return 0 }
        return min(100, monitor.dailyIncrease / todayCap * 100)
    }
}

private struct RefreshSettingsView: View {
    @ObservedObject var monitor: UsageMonitor
    @EnvironmentObject private var localization: AppLocalization
    let onDone: () -> Void

    @State private var selectedSchedule: RefreshSchedule
    @State private var selectedDailyRefreshTime: Date
    @State private var selectedTokenUnitStyle: TokenUnitStyle
    @State private var selectedAlertThresholds: DailyAlertThresholds
    @State private var selectedLanguage: AppLanguage
    @State private var showingReleaseNotes = false
    @State private var showingThresholdSettings = false

    init(monitor: UsageMonitor, onDone: @escaping () -> Void) {
        self.monitor = monitor
        self.onDone = onDone
        _selectedSchedule = State(initialValue: monitor.refreshSchedule)
        _selectedDailyRefreshTime = State(initialValue: monitor.dailyRefreshTime)
        _selectedTokenUnitStyle = State(initialValue: monitor.tokenUnitStyle)
        _selectedAlertThresholds = State(initialValue: monitor.alertThresholds)
        _selectedLanguage = State(initialValue: AppLocalization.shared.selection)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.045, green: 0.085, blue: 0.17),
                    Color(red: 0.025, green: 0.045, blue: 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("偏好设置", "Preferences"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(L(
                            "语言、自动刷新与数据读取设置",
                            "Language, refresh, and data access"
                        ))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    Spacer()
                    Button {
                        saveAndClose()
                    } label: {
                        Text(L("完成", "Done"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.horizontal, 4)
                    }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.00, green: 0.58, blue: 0.72))
                        .keyboardShortcut(.defaultAction)
                }

                Picker(
                    L("刷新频率", "Refresh frequency"),
                    selection: $selectedSchedule
                ) {
                    ForEach(RefreshSchedule.allCases) { schedule in
                        Text(localization.refreshScheduleTitle(schedule)).tag(schedule)
                    }
                }
                .pickerStyle(.radioGroup)
                .foregroundStyle(.white)

                if selectedSchedule == .daily {
                    HStack {
                        Label(
                            L("每天刷新时间", "Daily refresh time"),
                            systemImage: "calendar.badge.clock"
                        )
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        DatePicker(
                            "",
                            selection: $selectedDailyRefreshTime,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.field)
                    }
                    .padding(11)
                    .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.cyan.opacity(0.16), lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("界面语言", "Language"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))

                    Picker(L("界面语言", "Language"), selection: $selectedLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(localization.languageTitle(language)).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .onChange(of: selectedLanguage) { language in
                        localization.setLanguage(language)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Token 数量单位", "Token units"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))

                    Picker(
                        L("Token 数量单位", "Token units"),
                        selection: $selectedTokenUnitStyle
                    ) {
                        ForEach(TokenUnitStyle.allCases) { style in
                            Text(localization.tokenUnitTitle(style)).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                Button {
                    showingThresholdSettings = true
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("每日额度与预警阈值", "Daily cap and alert thresholds"))
                                .font(.system(size: 10.5, weight: .medium))
                            Text(thresholdSummary)
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(10)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Codex 数据来源", "Codex data source"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))

                    HStack(spacing: 10) {
                        Image(systemName: "externaldrive.badge.checkmark")
                            .foregroundStyle(.cyan)
                        Text(monitor.codexSourceSummary)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                        Spacer()
                        Button(L("选择…", "Select")) {
                            monitor.chooseCodexLocation()
                        }
                        .buttonStyle(.bordered)

                        if monitor.codexSelectionName != nil {
                            Button(L("恢复自动", "Auto")) {
                                monitor.clearCodexLocation()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Codex 登录资料", "Codex sign-in data"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))

                    HStack(spacing: 10) {
                        Image(systemName: "key.horizontal.fill")
                            .foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(monitor.codexHomeSourceSummary)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                            Text(L(
                                "只授权给本机 Codex 读取，本应用不解析账号内容",
                                "Used only by local Codex; never parsed by this app"
                            ))
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.42))
                        }
                        Spacer()
                        Button(L("授权…", "Allow")) {
                            monitor.chooseCodexHomeLocation()
                        }
                        .buttonStyle(.bordered)

                        if monitor.codexHomeSelectionName != nil {
                            Button(L("移除", "Remove")) {
                                monitor.clearCodexHomeLocation()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                }

                Divider().overlay(Color.white.opacity(0.08))

                Button {
                    monitor.openNotificationSettings()
                } label: {
                    HStack {
                        Label(
                            L("打开 macOS 通知设置", "Open macOS notification settings"),
                            systemImage: "bell.badge.fill"
                        )
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .foregroundStyle(.white.opacity(0.82))
                }
                .buttonStyle(.plain)

                Divider().overlay(Color.white.opacity(0.08))

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("当前版本", "Current version"))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.45))
                        Text(AppVersionInfo.displayName(isChinese: localization.isChinese))
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.86))
                    }

                    Spacer()

                    Button {
                        showingReleaseNotes = true
                    } label: {
                        Label(L("查看更新记录", "View updates"), systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        .frame(width: 330)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .overlay {
            if showingThresholdSettings {
                ThresholdSettingsView(
                    thresholds: selectedAlertThresholds,
                    onSave: { thresholds in
                        selectedAlertThresholds = thresholds
                        monitor.applySettings(
                            refreshSchedule: selectedSchedule,
                            dailyRefreshTime: selectedDailyRefreshTime,
                            tokenUnitStyle: selectedTokenUnitStyle,
                            alertThresholds: thresholds
                        )
                        showingThresholdSettings = false
                    },
                    onCancel: {
                        showingThresholdSettings = false
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if showingReleaseNotes {
                ReleaseNotesView {
                    showingReleaseNotes = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: showingReleaseNotes)
        .animation(.easeOut(duration: 0.16), value: showingThresholdSettings)
    }

    private func saveAndClose() {
        monitor.applySettings(
            refreshSchedule: selectedSchedule,
            dailyRefreshTime: selectedDailyRefreshTime,
            tokenUnitStyle: selectedTokenUnitStyle,
            alertThresholds: selectedAlertThresholds
        )
        localization.setLanguage(selectedLanguage)
        onDone()
    }

    private var thresholdSummary: String {
        selectedAlertThresholds.values
            .map(UsageMonitor.percent)
            .joined(separator: " · ") + "%"
    }
}

private struct ThresholdSettingsView: View {
    let onSave: (DailyAlertThresholds) -> Void
    let onCancel: () -> Void
    @State private var notice: Double
    @State private var reminder: Double
    @State private var high: Double
    @State private var baseCap: Double
    @State private var previousBaseCap: Double
    @State private var noticeRatio: Double
    @State private var reminderRatio: Double
    @State private var highRatio: Double

    init(
        thresholds: DailyAlertThresholds,
        onSave: @escaping (DailyAlertThresholds) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let values = thresholds.normalized
        self.onSave = onSave
        self.onCancel = onCancel
        _notice = State(initialValue: values.notice)
        _reminder = State(initialValue: values.reminder)
        _high = State(initialValue: values.high)
        _baseCap = State(initialValue: values.baseCap)
        _previousBaseCap = State(initialValue: values.baseCap)
        _noticeRatio = State(initialValue: values.notice / values.baseCap)
        _reminderRatio = State(initialValue: values.reminder / values.baseCap)
        _highRatio = State(initialValue: values.high / values.baseCap)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.045, green: 0.085, blue: 0.17),
                    Color(red: 0.025, green: 0.045, blue: 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("每日额度与预警阈值", "Daily cap and alert thresholds"))
                            .font(.system(size: 15.5, weight: .semibold))
                        Text(L(
                            "单位为用量百分比，可输入 0.5–100",
                            "Quota percentage points · enter 0.5–100"
                        ))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.46))
                    }
                    Spacer()
                    Button(L("取消", "Cancel"), action: onCancel)
                        .buttonStyle(.borderless)
                }

                VStack(spacing: 9) {
                    ThresholdEditorRow(
                        label: L("注意", "Notice"),
                        value: noticeBinding,
                        tint: .cyan
                    )
                    ThresholdEditorRow(
                        label: L("提醒", "Reminder"),
                        value: reminderBinding,
                        tint: .yellow
                    )
                    ThresholdEditorRow(
                        label: L("偏高", "High"),
                        value: highBinding,
                        tint: .orange
                    )
                    ThresholdEditorRow(
                        label: L("基础上限", "Base cap"),
                        value: $baseCap,
                        tint: .red
                    )
                }

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.cyan.opacity(0.8))
                    Text(L(
                        "修改基础上限时，前三档会自动等比例缩放；随后仍可单独调整。保存时会保证四档从小到大排列。",
                        "Changing the base cap scales the first three levels proportionally. Each level can still be edited separately; values are ordered when saved."
                    ))
                }
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))

                HStack {
                    Button(L("按比例重置", "Reset proportions")) {
                        noticeRatio = 0.25
                        reminderRatio = 0.5
                        highRatio = 0.75
                        scaleThresholds(to: baseCap, force: true)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(L("保存", "Save")) {
                        onSave(currentThresholds.normalized)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.00, green: 0.58, blue: 0.72))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 330)
        .preferredColorScheme(.dark)
        .onChange(of: baseCap) { newValue in
            scaleThresholds(to: newValue)
        }
    }

    private var currentThresholds: DailyAlertThresholds {
        DailyAlertThresholds(
            notice: notice,
            reminder: reminder,
            high: high,
            baseCap: baseCap
        )
    }

    private var noticeBinding: Binding<Double> {
        Binding(
            get: { notice },
            set: { newValue in
                notice = newValue
                if baseCap > 0 { noticeRatio = newValue / baseCap }
            }
        )
    }

    private var reminderBinding: Binding<Double> {
        Binding(
            get: { reminder },
            set: { newValue in
                reminder = newValue
                if baseCap > 0 { reminderRatio = newValue / baseCap }
            }
        )
    }

    private var highBinding: Binding<Double> {
        Binding(
            get: { high },
            set: { newValue in
                high = newValue
                if baseCap > 0 { highRatio = newValue / baseCap }
            }
        )
    }

    private func scaleThresholds(to newBaseCap: Double, force: Bool = false) {
        guard previousBaseCap > 0,
              newBaseCap >= 0.5,
              newBaseCap <= 100,
              force || newBaseCap != previousBaseCap else { return }
        notice = roundedThreshold(newBaseCap * noticeRatio)
        reminder = roundedThreshold(newBaseCap * reminderRatio)
        high = roundedThreshold(newBaseCap * highRatio)
        previousBaseCap = newBaseCap
    }

    private func roundedThreshold(_ value: Double) -> Double {
        min(100, max(0.5, (value * 10).rounded() / 10))
    }
}

private struct ThresholdEditorRow: View {
    let label: String
    @Binding var value: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField(
                "",
                value: $value,
                format: .number.precision(.fractionLength(0...1))
            )
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 62)
            Text("%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))
            Stepper("", value: $value, in: 0.5...100, step: 0.5)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
    }
}

private enum AppVersionInfo {
    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
    }

    static var buildNumber: Int {
        let rawValue = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "0"
        return Int(rawValue) ?? 0
    }

    static func displayName(isChinese: Bool) -> String {
        if isChinese {
            return "V\(marketingVersion)（build \(buildNumber)）"
        }
        return "V\(marketingVersion) (build \(buildNumber))"
    }

    static func marketingVersion(for build: Int) -> String {
        "\(build / 100).\((build / 10) % 10).\(build % 10)"
    }
}

private struct ReleaseNote: Identifiable {
    let build: Int
    let chineseItems: [String]
    let englishItems: [String]

    var id: Int { build }
    var version: String { AppVersionInfo.marketingVersion(for: build) }
}

private enum ReleaseNotes {
    static let all: [ReleaseNote] = [
        ReleaseNote(
            build: 26,
            chineseItems: [
                "Token 图表固定显示截至今天的最近 7 个本机自然日。",
                "前六列增加星期标签，最后一列明确标记为今天。",
                "按数据顺序消除服务端日期空档，浮窗同步显示适配后的星期和日期。",
            ],
            englishItems: [
                "Always show the latest seven local calendar days ending today in the token chart.",
                "Add weekday labels to the first six columns and mark the final column as Today.",
                "Remove raw server-date gaps by mapping entries in order, with aligned weekdays and dates in the detail card.",
            ]
        ),
        ReleaseNote(
            build: 25,
            chineseItems: [
                "将 Token 柱状图悬停浮窗移到图表上方，避免遮挡柱形。",
                "增加指向当前柱形的引导线和高亮端点。",
                "支持点击柱形显示或收起详情，并补充辅助功能标签。",
            ],
            englishItems: [
                "Move the token chart hover card above the plot so it never covers a bar.",
                "Add a leader line and highlighted endpoint pointing to the active bar.",
                "Allow clicking a bar to show or hide details, with accessibility labels for every bar.",
            ]
        ),
        ReleaseNote(
            build: 24,
            chineseItems: [
                "为额度概览、今日预算、Token、重置时间、额度周期和预警刻度增加独立 info 浮窗。",
                "将计算公式、数据来源、日期适配和阈值解释从主页面移入对应浮窗。",
                "连接异常、Token 不可用和沙盒授权区域也提供独立说明入口。",
            ],
            englishItems: [
                "Add dedicated info popovers for usage overview, daily budget, tokens, reset time, usage window, and alert levels.",
                "Move formulas, data sources, date alignment, and threshold explanations from the dashboard into their matching popovers.",
                "Add contextual info popovers for connection errors, unavailable token data, and sandbox authorization.",
            ]
        ),
        ReleaseNote(
            build: 23,
            chineseItems: [
                "服务端最新 Token 每日统计固定显示为本机今天，上一条显示为昨天。",
                "图表日期和本月累计同步使用相同的本机日期适配规则。",
                "保留服务端原始日期用于排查，不再把时区差异显示成今日数据缺失。",
            ],
            englishItems: [
                "Show the latest server daily token total as today and the previous total as yesterday.",
                "Apply the same local date alignment to chart labels and month-to-date totals.",
                "Keep raw server dates for diagnostics without presenting timezone differences as missing data.",
            ]
        ),
        ReleaseNote(
            build: 22,
            chineseItems: [
                "Token 卡片改为显示今日、昨日和本月累计，并为柱状图增加悬停详情。",
                "支持分别设置注意、提醒、偏高和基础上限四档额度阈值。",
                "修改基础上限时自动等比例缩放前三档，同时允许继续单独调整。",
                "统一优化每日统计、周期起点和本机记录等中文说明。",
            ],
            englishItems: [
                "Show today, yesterday, and month-to-date tokens with hover details on chart bars.",
                "Configure Notice, Reminder, High, and Base Cap thresholds independently.",
                "Scale the first three thresholds proportionally when the base cap changes, while keeping individual editing available.",
                "Clarify the sustainable average label as the quota-window daily average.",
            ]
        ),
        ReleaseNote(
            build: 21,
            chineseItems: [
                "关闭主界面或按 Command + Q 后继续在菜单栏后台监控，并提供首次使用提示。",
                "菜单栏电源按钮支持完全退出应用。",
                "根据 Git 提交次数自动同步版本号和 Build。",
                "在设置中增加当前版本与完整更新记录。",
            ],
            englishItems: [
                "Keep monitoring in the menu bar after closing the dashboard or pressing Command-Q, with a first-use explanation.",
                "Quit completely from the power button in the menu bar panel.",
                "Automatically synchronize the version and build number with the Git commit count.",
                "Show the current version and complete update history in Preferences.",
            ]
        ),
        ReleaseNote(build: 20, chineseItems: ["用单一状态色显示今日用量圆环，避免渐变颜色造成误解。"], englishItems: ["Use one status color for the daily usage ring to avoid misleading gradients."]),
        ReleaseNote(build: 19, chineseItems: ["自动显示隐藏的 .codex 文件夹，简化沙盒授权。"], englishItems: ["Reveal the hidden .codex folder automatically during sandbox authorization."]),
        ReleaseNote(build: 18, chineseItems: ["重排首页信息优先级，并加入简体中文与英文界面。"], englishItems: ["Prioritize the most important dashboard data and add Chinese and English interfaces."]),
        ReleaseNote(build: 17, chineseItems: ["明确服务端与本机数据来源，并增加启动 Codex/ChatGPT 的引导。"], englishItems: ["Clarify server and local data sources and add guidance for opening Codex/ChatGPT."]),
        ReleaseNote(build: 16, chineseItems: ["增加 Developer ID 签名、DMG 打包与 Apple 公证流程。"], englishItems: ["Add Developer ID signing, DMG packaging, and Apple notarization workflows."]),
        ReleaseNote(build: 15, chineseItems: ["更新应用图标并记录开发版与发布版的构建策略。"], englishItems: ["Refresh the app icon and document development and release build variants."]),
        ReleaseNote(build: 14, chineseItems: ["在额度基线可用后自动重新计算结转预算。"], englishItems: ["Recalculate rollover budget automatically when a quota baseline becomes available."]),
        ReleaseNote(build: 13, chineseItems: ["完成沙盒环境下的 Codex 用量读取验证。"], englishItems: ["Validate Codex usage access inside the App Sandbox."]),
        ReleaseNote(build: 12, chineseItems: ["改进彩色菜单栏图标。"], englishItems: ["Improve the full-color menu bar icon."]),
        ReleaseNote(build: 11, chineseItems: ["增加周期起点估算并澄清 Token 日期含义。"], englishItems: ["Add quota-window baseline estimates and clarify token bucket dates."]),
        ReleaseNote(build: 10, chineseItems: ["增加符合沙盒要求的 Codex 程序与登录资料授权。"], englishItems: ["Add sandbox-safe authorization for the Codex app and sign-in data."]),
        ReleaseNote(build: 9, chineseItems: ["修正结转上限计算和 Token 日期状态。"], englishItems: ["Correct rollover cap calculations and token date status."]),
        ReleaseNote(build: 8, chineseItems: ["明确缺失昨日数据时的结转来源和展示方式。"], englishItems: ["Clarify rollover sources and presentation when yesterday's data is unavailable."]),
        ReleaseNote(build: 7, chineseItems: ["增加每日可持续用量和昨日余量结转预算。"], englishItems: ["Add sustainable daily usage and unused-budget rollover."]),
        ReleaseNote(build: 6, chineseItems: ["记录免费分发方案和项目网站。"], englishItems: ["Document free distribution and the project website."]),
        ReleaseNote(build: 5, chineseItems: ["建立 App Store 开发计划和项目文档库。"], englishItems: ["Create the App Store development plan and documentation library."]),
        ReleaseNote(build: 4, chineseItems: ["统一主窗口和菜单栏中的设置面板。"], englishItems: ["Unify Preferences across the dashboard and menu bar panel."]),
        ReleaseNote(build: 3, chineseItems: ["修复菜单栏弹窗中的设置交互。"], englishItems: ["Fix Preferences interactions inside the menu bar popover."]),
        ReleaseNote(build: 2, chineseItems: ["修复设置保存和菜单栏图标。"], englishItems: ["Fix settings persistence and the menu bar icon."]),
        ReleaseNote(build: 1, chineseItems: ["完成第一个开源版本。"], englishItems: ["Publish the initial open-source version."]),
    ]
}

private struct ReleaseNotesView: View {
    @EnvironmentObject private var localization: AppLocalization
    let onDone: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.045, green: 0.085, blue: 0.17),
                    Color(red: 0.025, green: 0.045, blue: 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("更新记录", "What's new"))
                            .font(.system(size: 16, weight: .semibold))
                        Text(AppVersionInfo.displayName(isChinese: localization.isChinese))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.cyan.opacity(0.82))
                    }
                    Spacer()
                    Button(L("完成", "Done"), action: onDone)
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.00, green: 0.58, blue: 0.72))
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(ReleaseNotes.all) { note in
                            releaseCard(note)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(20)
        }
        .foregroundStyle(.white)
    }

    private func releaseCard(_ note: ReleaseNote) -> some View {
        let items = localization.isChinese ? note.chineseItems : note.englishItems
        return VStack(alignment: .leading, spacing: 7) {
            Text(versionTitle(note))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(note.build == AppVersionInfo.buildNumber ? .cyan : .white.opacity(0.82))

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Text("\(index + 1). \(item)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    note.build == AppVersionInfo.buildNumber
                        ? Color.cyan.opacity(0.18)
                        : Color.white.opacity(0.055),
                    lineWidth: 1
                )
        )
    }

    private func versionTitle(_ note: ReleaseNote) -> String {
        if localization.isChinese {
            return "V\(note.version)（build \(note.build)）"
        }
        return "V\(note.version) (build \(note.build))"
    }
}

private struct UsageGauge: View {
    let progressPercent: Double
    let primaryPercent: Double
    let label: String
    let secondaryText: String
    let color: Color
    let isRefreshing: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 13)

            Circle()
                .trim(from: 0, to: max(0.012, min(progressPercent / 100, 1)))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.42), radius: 7)
                .animation(.easeOut(duration: 0.5), value: progressPercent)

            VStack(spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(UsageMonitor.percent(primaryPercent))
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(secondaryText)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(color.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            if isRefreshing {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 2)
                    .frame(width: 84, height: 84)
            }
        }
        .frame(width: 126, height: 126)
    }
}

private struct MetricRow: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.44))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }
}

private struct InfoPopoverSection: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let text: String
}

private struct InfoPopoverButton: View {
    let title: String
    let sections: [InfoPopoverSection]
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.cyan.opacity(0.82))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 7) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.cyan)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }

                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    if index > 0 {
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: section.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.cyan.opacity(0.86))
                            .frame(width: 17, height: 17)
                            .background(Color.cyan.opacity(0.09), in: RoundedRectangle(cornerRadius: 5))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(section.title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                            Text(section.text)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.white.opacity(0.60))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(15)
            .frame(width: 310)
            .background(Color(red: 0.035, green: 0.055, blue: 0.11))
            .preferredColorScheme(.dark)
        }
    }
}

private struct DailyBudgetCard: View {
    let dailyIncrease: Double
    let statusColor: Color
    let budget: DailyBudgetRollover?
    let thresholds: DailyAlertThresholds
    @EnvironmentObject private var localization: AppLocalization

    private var cap: Double {
        max(1, budget?.todayAvailablePercent ?? thresholds.baseCap)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("今日额度预算", "Today's budget"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                InfoPopoverButton(
                    title: L("今日额度预算说明", "Today's budget"),
                    sections: infoSections
                )
                Spacer()
                Text(
                    "\(UsageMonitor.percent(dailyIncrease)) / \(UsageMonitor.percent(cap))%"
                )
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusColor)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.075))
                        .frame(height: 8)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.cyan, statusColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geometry.size.width * min(max(dailyIncrease / cap, 0), 1),
                            height: 8
                        )
                        .shadow(color: statusColor.opacity(0.38), radius: 5)

                    ForEach(thresholds.values, id: \.self) { threshold in
                        Circle()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 5, height: 5)
                            .offset(
                                x: max(
                                    0,
                                    min(geometry.size.width - 5, geometry.size.width * threshold / cap - 2.5)
                                )
                            )
                    }
                }
                .frame(height: 8)
            }
            .frame(height: 8)

            HStack(spacing: 0) {
                RuleLabel(
                    value: UsageMonitor.percent(thresholds.notice),
                    label: L("注意", "Notice")
                )
                RuleLabel(
                    value: UsageMonitor.percent(thresholds.reminder),
                    label: L("提醒", "Alert")
                )
                RuleLabel(
                    value: UsageMonitor.percent(thresholds.high),
                    label: L("偏高", "High")
                )
                RuleLabel(
                    value: UsageMonitor.percent(thresholds.baseCap),
                    label: L("基础上限", "Base cap")
                )
            }

            Divider().overlay(Color.white.opacity(0.07))

            HStack(spacing: 0) {
                BudgetInputValue(
                    value: formatted(budget?.sustainableDailyBudgetPercent),
                    label: L("每日建议", "Sustainable")
                )
                BudgetInputValue(
                    value: yesterdayUsedValue,
                    label: budget?.yesterdayUsageSource == .windowBaselineEstimate
                        ? L("昨日估算", "Yesterday est.")
                        : L("昨日已用", "Yesterday")
                )
                BudgetInputValue(
                    value: "+\(formatted(budget?.carriedPercent))",
                    label: L("昨日余量", "Carryover")
                )
                BudgetInputValue(
                    value: formatted(budget?.baseDailyCapPercent ?? thresholds.baseCap),
                    label: L("基础上限", "Base cap")
                )
                BudgetInputValue(
                    value: formatted(budget?.todayAvailablePercent ?? thresholds.baseCap),
                    label: L("今日上限", "Today cap")
                )
            }

        }
        .padding(13)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.065), lineWidth: 1))
    }

    private var sourceDescription: String {
        guard let budget else {
            return L(
                "每日建议：等待服务端 · 昨日：暂无本机记录 · \(baseCapText)：个人设置",
                "Sustainable: waiting for App Server · Yesterday: no local snapshot · \(baseCapText): personal rule"
            )
        }
        if budget.hasYesterdayData {
            let sourceDay = budget.sourceDay ?? L("昨日", "Yesterday")
            if budget.yesterdayUsageSource == .windowBaselineEstimate {
                return L(
                    "每日建议：服务端 · \(sourceDay)：根据周期起点估算 · \(baseCapText)：个人设置",
                    "Sustainable: App Server · \(sourceDay): window baseline estimate · \(baseCapText): personal rule"
                )
            }
            return L(
                "每日建议：服务端 · \(sourceDay)：本机每日记录 · \(baseCapText)：个人设置",
                "Sustainable: App Server · \(sourceDay): local daily snapshot · \(baseCapText): personal rule"
            )
        }
        return L(
            "每日建议：服务端 · 昨日：暂无本机记录 · \(baseCapText)：个人设置",
            "Sustainable: App Server · Yesterday: no local snapshot · \(baseCapText): personal rule"
        )
    }

    private var infoSections: [InfoPopoverSection] {
        var sections = [
            InfoPopoverSection(
                icon: "function",
                title: L("今日上限计算", "Today's cap calculation"),
                text: formulaDescription
            ),
            InfoPopoverSection(
                icon: "arrow.triangle.2.circlepath",
                title: L("每日建议与结转", "Sustainable pace and rollover"),
                text: sourceHelp
            ),
            InfoPopoverSection(
                icon: "server.rack",
                title: L("数据来源", "Data sources"),
                text: sourceDescription
            ),
            InfoPopoverSection(
                icon: "bell.badge.fill",
                title: L("预警刻度", "Alert thresholds"),
                text: L(
                    "进度条上的四个刻度分别是 \(UsageMonitor.percent(thresholds.notice))%、\(UsageMonitor.percent(thresholds.reminder))%、\(UsageMonitor.percent(thresholds.high))% 和 \(UsageMonitor.percent(thresholds.baseCap))%。它们都可以在设置中修改。",
                    "The four progress thresholds are \(UsageMonitor.percent(thresholds.notice))%, \(UsageMonitor.percent(thresholds.reminder))%, \(UsageMonitor.percent(thresholds.high))%, and \(UsageMonitor.percent(thresholds.baseCap))%. All can be changed in Settings."
                )
            ),
        ]
        if let budget, !budget.hasYesterdayData {
            sections.append(
                InfoPopoverSection(
                    icon: "desktopcomputer.trianglebadge.exclamationmark",
                    title: L("本机记录范围", "Local history limits"),
                    text: L(
                        "此设备从首次刷新开始记录，无法回溯其他电脑或首次刷新前的今日增量；周期已用与剩余仍来自账号实时数据。",
                        "This device records from its first refresh. Earlier or other-device activity is not included in today's local increase; window usage remains live account data."
                    )
                )
            )
        }
        return sections
    }

    private var formulaDescription: String {
        guard let budget, budget.hasYesterdayData else {
            return L(
                "今日上限 \(baseCapText)；此设备有完整的昨日记录后，再加上昨日未用的建议额度。",
                "Today's cap is \(baseCapText). Unused sustainable budget rolls over after a full local snapshot day."
            )
        }
        return L(
            "今日上限 = \(formatted(budget.baseDailyCapPercent)) + \(formatted(budget.carriedPercent)) = \(formatted(budget.todayAvailablePercent))",
            "Today's cap = \(formatted(budget.baseDailyCapPercent)) + \(formatted(budget.carriedPercent)) = \(formatted(budget.todayAvailablePercent))"
        )
    }

    private var sourceHelp: String {
        if budget?.yesterdayUsageSource == .windowBaselineEstimate {
            return L(
                "每日建议来自服务端额度周期（100 ÷ 周期天数）。当前周期从昨日开始，因此使用今天首次记录的周期累计值估算昨日用量；该估算可能包含今天首次记录前的用量。\(baseCapText) 是你的个人设置。",
                "Sustainable pace comes from account/rateLimits/read (100 ÷ window days). Because this window began yesterday, yesterday is estimated from today's first window baseline and may include early-today usage. The \(baseCapText) cap is your personal rule."
            )
        }
        return L(
            "每日建议来自服务端额度周期（100 ÷ 周期天数）；昨日已用根据本机同一天的用量记录计算。\(baseCapText) 是你的个人每日基础上限，不是 OpenAI 官方硬限制；缺少昨日记录时不会按 0 计算或结转。",
            "Sustainable pace comes from account/rateLimits/read (100 ÷ window days). Yesterday comes from local snapshot differences. The \(baseCapText) base cap is your personal rule, not an official OpenAI hard limit. Missing days are neither treated as zero nor rolled over."
        )
    }

    private var yesterdayUsedValue: String {
        let value = formatted(budget?.yesterdayUsedPercent)
        if budget?.yesterdayUsageSource == .windowBaselineEstimate {
            return "≈\(value)"
        }
        return value
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(UsageMonitor.percent(value))%"
    }

    private var baseCapText: String {
        "\(UsageMonitor.percent(thresholds.baseCap))%"
    }
}

private struct RuleLabel: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 2) {
            Text(value)
                .fontWeight(.semibold)
            Text(label)
        }
        .font(.system(size: 7.6))
        .foregroundStyle(.white.opacity(0.38))
        .frame(maxWidth: .infinity)
    }
}

private struct BudgetInputValue: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.system(size: 7.8))
                .foregroundStyle(.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TokenUsageCard: View {
    let usage: AccountTokenUsage
    let unitStyle: TokenUnitStyle
    @EnvironmentObject private var localization: AppLocalization
    @State private var hoveredBucketID: String?

    private var recentBuckets: [DailyTokenUsage] {
        Array(usage.orderedDailyUsageBuckets.suffix(7))
    }

    private var maximumTokens: Double {
        Double(max(recentBuckets.map(\.tokens).max() ?? 0, 1))
    }

    private var latestUsageDate: String? {
        usage.latestUsageDate()
    }

    private var todayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "number.circle.fill")
                        .foregroundStyle(.cyan)
                    Text(L("账号 Token 使用量", "Account token usage"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    InfoPopoverButton(
                        title: L("Token 使用量说明", "Token usage"),
                        sections: infoSections
                    )
                }

                Spacer()

                Text(
                    L(
                        "总累计 \(TokenCountFormatter.compact(usage.summary.lifetimeTokens, style: unitStyle))",
                        "Lifetime \(TokenCountFormatter.compact(usage.summary.lifetimeTokens, style: unitStyle))"
                    )
                )
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.cyan.opacity(0.85))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.09), in: Capsule())
            }

            HStack(spacing: 0) {
                TokenMetric(
                    value: TokenCountFormatter.compact(
                        usage.todayTokens(),
                        style: unitStyle
                    ),
                    label: L("今日用量", "Today")
                )
                Divider().overlay(Color.white.opacity(0.08))
                TokenMetric(
                    value: TokenCountFormatter.compact(
                        usage.yesterdayTokens(),
                        style: unitStyle
                    ),
                    label: L("昨日用量", "Yesterday")
                )
                Divider().overlay(Color.white.opacity(0.08))
                TokenMetric(
                    value: TokenCountFormatter.compact(
                        usage.monthToDateTokens(),
                        style: unitStyle
                    ),
                    label: monthToDateLabel
                )
            }
            .frame(height: 35)

            if recentBuckets.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis")
                    Text(L("暂时没有每日 Token 趋势数据", "No daily token trend data yet"))
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.42))
                .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                GeometryReader { geometry in
                    let tooltipWidth: CGFloat = 126
                    let tooltipHeight: CGFloat = 45
                    let chartTop: CGFloat = 52
                    let chartHeight: CGFloat = 64
                    let barAreaHeight = chartHeight - 26

                    ZStack(alignment: .topLeading) {
                        HStack(alignment: .bottom, spacing: 7) {
                            ForEach(recentBuckets) { bucket in
                                VStack(spacing: 4) {
                                    Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(
                                            LinearGradient(
                                                colors: [.cyan.opacity(0.65), .cyan],
                                                startPoint: .bottom,
                                                endPoint: .top
                                            )
                                        )
                                        .frame(
                                            height: max(
                                                4,
                                                barAreaHeight
                                                    * CGFloat(Double(bucket.tokens) / maximumTokens)
                                            )
                                        )
                                        .shadow(color: .cyan.opacity(0.22), radius: 3)
                                    VStack(spacing: 0) {
                                        Text(dayLabel(for: bucket))
                                            .font(.system(size: 7.2, weight: .semibold, design: .rounded))
                                            .foregroundStyle(
                                                isToday(bucket)
                                                    ? Color.cyan.opacity(0.88)
                                                    : Color.white.opacity(0.43)
                                            )
                                        Text(shortDate(adaptedDateKey(for: bucket)))
                                            .font(.system(size: 7.1, weight: .medium, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.32))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .opacity(hoveredBucketID == nil || hoveredBucketID == bucket.id ? 1 : 0.48)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(
                                    L(
                                        "\(dayLabel(for: bucket)) \(shortDate(adaptedDateKey(for: bucket))) Token 用量",
                                        "Token usage on \(dayLabel(for: bucket)) \(shortDate(adaptedDateKey(for: bucket)))"
                                    )
                                )
                                .accessibilityValue(
                                    "\(TokenCountFormatter.compact(bucket.tokens, style: unitStyle))"
                                )
                                .accessibilityAddTraits(.isButton)
                                .onTapGesture {
                                    withAnimation(.easeOut(duration: 0.12)) {
                                        hoveredBucketID = hoveredBucketID == bucket.id
                                            ? nil
                                            : bucket.id
                                    }
                                }
                                .onHover { isHovering in
                                    withAnimation(.easeOut(duration: 0.12)) {
                                        hoveredBucketID = isHovering ? bucket.id : nil
                                    }
                                }
                            }
                        }
                        .frame(width: geometry.size.width, height: chartHeight)
                        .offset(y: chartTop)

                        if let hoveredBucket,
                           let index = recentBuckets.firstIndex(where: { $0.id == hoveredBucket.id }) {
                            let tooltipX = tooltipOffset(
                                index: index,
                                chartWidth: geometry.size.width
                            )
                            let barCenterX = barCenter(
                                index: index,
                                chartWidth: geometry.size.width
                            )
                            let hoveredBarHeight = max(
                                4,
                                barAreaHeight
                                    * CGFloat(Double(hoveredBucket.tokens) / maximumTokens)
                            )
                            let barTopY = chartTop + barAreaHeight - hoveredBarHeight

                            Path { path in
                                path.move(
                                    to: CGPoint(
                                        x: tooltipX + tooltipWidth / 2,
                                        y: tooltipHeight
                                    )
                                )
                                path.addLine(
                                    to: CGPoint(
                                        x: barCenterX,
                                        y: max(tooltipHeight + 3, barTopY - 3)
                                    )
                                )
                            }
                            .stroke(
                                Color.cyan.opacity(0.58),
                                style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
                            )
                            .allowsHitTesting(false)
                            .zIndex(1)

                            Circle()
                                .fill(Color.cyan)
                                .frame(width: 4, height: 4)
                                .offset(x: barCenterX - 2, y: max(tooltipHeight + 1, barTopY - 5))
                                .shadow(color: .cyan.opacity(0.55), radius: 2)
                                .allowsHitTesting(false)
                                .zIndex(1)

                            TokenBarTooltip(
                                bucket: hoveredBucket,
                                displayDate: tooltipDateLabel(for: hoveredBucket),
                                unitStyle: unitStyle
                            )
                                .frame(width: 126)
                                .offset(
                                    x: tooltipX,
                                    y: 0
                                )
                                .allowsHitTesting(false)
                                .zIndex(2)
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                }
                .frame(height: 116)
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.cyan.opacity(0.12), lineWidth: 1))
    }

    private var hoveredBucket: DailyTokenUsage? {
        recentBuckets.first(where: { $0.id == hoveredBucketID })
    }

    private var monthToDateLabel: String {
        latestUsageDate == nil
            ? L("本月暂无日汇总", "No monthly summary")
            : L("本月累计", "Month to date")
    }

    private var infoSections: [InfoPopoverSection] {
        let rawDate = latestUsageDate ?? L("暂无", "Unavailable")
        return [
            InfoPopoverSection(
                icon: "calendar.badge.clock",
                title: L("今日与昨日", "Today and yesterday"),
                text: L(
                    "服务端最新一条每日统计固定显示为今天，上一条显示为昨天；最新 7 条按顺序对应本机最近 7 个自然日。服务端最新原始日期为 \(rawDate)，本机系统日期为 \(todayKey)。",
                    "The latest server daily total is shown as today and the previous total as yesterday. The latest seven entries map in order to the latest seven local calendar days. The latest raw server date is \(rawDate), while this Mac reports \(todayKey)."
                )
            ),
            InfoPopoverSection(
                icon: "sum",
                title: L("本月累计", "Month to date"),
                text: L(
                    "本月累计会先把每日统计日期适配到本机日期，再汇总本机当前月份内的数据。",
                    "Month to date first aligns daily totals to this Mac's dates, then sums entries in the current local month."
                )
            ),
            InfoPopoverSection(
                icon: "number.circle.fill",
                title: L("精确数值", "Exact totals"),
                text: L(
                    "今日：\(exactTokens(usage.todayTokens())) Token；昨日：\(exactTokens(usage.yesterdayTokens())) Token；本月：\(exactTokens(usage.monthToDateTokens())) Token。",
                    "Today: \(exactTokens(usage.todayTokens())) tokens; yesterday: \(exactTokens(usage.yesterdayTokens())) tokens; month to date: \(exactTokens(usage.monthToDateTokens())) tokens."
                )
            ),
            InfoPopoverSection(
                icon: "chart.bar.fill",
                title: L("每日趋势", "Daily trend"),
                text: L(
                    "柱状图固定显示截至今天的最近 7 个本机自然日。前六列显示星期，最后一列标记为今天；浮窗会显示适配后的星期、日期和精确 Token 数。",
                    "The chart always shows the latest seven local calendar days ending today. The first six columns show weekdays and the final column is marked Today; the detail card shows the aligned weekday, date, and exact token count."
                )
            ),
            InfoPopoverSection(
                icon: "server.rack",
                title: L("数据来源", "Data source"),
                text: L(
                    "总累计和每日统计来自 Codex App Server account/usage/read。官方没有说明 startDate 的时区，原始日期仅保留用于排查。",
                    "Lifetime and daily totals come from Codex App Server account/usage/read. The startDate timezone is undocumented, so raw dates are retained only for diagnostics."
                )
            ),
        ]
    }

    private func exactTokens(_ value: Int64?) -> String {
        value?.formatted() ?? "--"
    }

    private func tooltipOffset(index: Int, chartWidth: CGFloat) -> CGFloat {
        let tooltipWidth: CGFloat = 126
        let center = barCenter(index: index, chartWidth: chartWidth)
        return min(max(0, center - tooltipWidth / 2), max(0, chartWidth - tooltipWidth))
    }

    private func barCenter(index: Int, chartWidth: CGFloat) -> CGFloat {
        let count = max(recentBuckets.count, 1)
        let spacing: CGFloat = 7
        let totalSpacing = spacing * CGFloat(max(0, count - 1))
        let columnWidth = max(0, chartWidth - totalSpacing) / CGFloat(count)
        return CGFloat(index) * (columnWidth + spacing) + columnWidth / 2
    }

    private func shortDate(_ value: String) -> String {
        let components = value.split(separator: "-")
        guard components.count == 3 else { return value }
        if localization.isChinese {
            return "\(components[1])/\(components[2])"
        }
        return "\(components[1])/\(components[2])"
    }

    private func adaptedDateKey(for bucket: DailyTokenUsage) -> String {
        usage.adaptedDateKey(for: bucket)
    }

    private func isToday(_ bucket: DailyTokenUsage) -> Bool {
        adaptedDateKey(for: bucket) == todayKey
    }

    private func dayLabel(for bucket: DailyTokenUsage) -> String {
        if isToday(bucket) {
            return L("今天", "Today")
        }
        return weekdayLabel(for: adaptedDateKey(for: bucket))
    }

    private func tooltipDateLabel(for bucket: DailyTokenUsage) -> String {
        "\(adaptedDateKey(for: bucket)) · \(dayLabel(for: bucket))"
    }

    private func weekdayLabel(for dateKey: String) -> String {
        let parts = dateKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar.current.date(
                  from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
              ) else { return dateKey }
        let weekday = Calendar.current.component(.weekday, from: date)
        if localization.isChinese {
            return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][weekday - 1]
        }
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][weekday - 1]
    }
}

private struct TokenBarTooltip: View {
    let bucket: DailyTokenUsage
    let displayDate: String
    let unitStyle: TokenUnitStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayDate)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(TokenCountFormatter.compact(bucket.tokens, style: unitStyle))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(L("\(bucket.tokens.formatted()) Token", "\(bucket.tokens.formatted()) tokens"))
                .font(.system(size: 7.5, design: .rounded))
                .foregroundStyle(.cyan.opacity(0.82))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.02, green: 0.04, blue: 0.09).opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 7, y: 3)
    }
}

private struct TokenMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 8.2))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
    }
}

private struct TokenUsageUnavailableCard: View {
    let isRefreshing: Bool
    let errorMessage: String?
    @EnvironmentObject private var localization: AppLocalization

    var body: some View {
        HStack(spacing: 9) {
            if isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "number.circle")
                    .foregroundStyle(.cyan)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L("账号 Token 使用量", "Account token usage"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text(isRefreshing
                     ? L("正在读取 Token 数据…", "Reading token data…")
                     : L("Token 数据暂不可用", "Token data unavailable"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.42))
            }
            Spacer()
            InfoPopoverButton(
                title: L("Token 数据说明", "Token data"),
                sections: [
                    InfoPopoverSection(
                        icon: "server.rack",
                        title: L("当前状态", "Current status"),
                        text: errorMessage ?? L(
                            "正在等待 Codex App Server 返回 Token 数据。额度监控不会因此停止。",
                            "Waiting for Codex App Server to return token data. Quota monitoring continues meanwhile."
                        )
                    ),
                    InfoPopoverSection(
                        icon: "arrow.up.forward.app.fill",
                        title: L("如何恢复", "How to restore data"),
                        text: L(
                            "请先打开并登录 Codex 或 ChatGPT/Codex 应用，然后回到这里点击立即刷新。",
                            "Open and sign in to Codex or the ChatGPT/Codex app, then return here and select Refresh now."
                        )
                    ),
                ]
            )
        }
        .padding(13)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}

private struct StatTile: View {
    let icon: String
    let value: String
    let detail: String
    let label: String
    let infoTitle: String
    let infoText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.cyan.opacity(0.85))
                Spacer(minLength: 0)
                InfoPopoverButton(
                    title: infoTitle,
                    sections: [
                        InfoPopoverSection(icon: icon, title: label, text: infoText),
                    ]
                )
            }
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(1)
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.055), lineWidth: 1))
    }
}

private struct ErrorBanner: View {
    let message: String
    let canOpenCodex: Bool
    let isLaunchingCodex: Bool
    let onOpenCodex: () -> Void
    @EnvironmentObject private var localization: AppLocalization

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(message)
                        .font(.system(size: 10.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.white.opacity(0.86))
                }
                Spacer(minLength: 0)
                InfoPopoverButton(
                    title: L("连接问题说明", "Connection issue"),
                    sections: [
                        InfoPopoverSection(
                            icon: "person.crop.circle.badge.checkmark",
                            title: L("登录状态", "Sign-in status"),
                            text: L(
                                "首次使用另一台电脑时，请先启动 Codex/ChatGPT 并确认账号已登录。",
                                "On a new Mac, open Codex/ChatGPT first and confirm that you are signed in."
                            )
                        ),
                        InfoPopoverSection(
                            icon: "arrow.clockwise",
                            title: L("重新读取", "Try again"),
                            text: L(
                                "登录完成后返回本应用，点击立即刷新。连接恢复后错误区域会自动消失。",
                                "Return to this app after signing in and select Refresh now. This error area disappears automatically when the connection recovers."
                            )
                        ),
                    ]
                )
            }

            if canOpenCodex {
                Button(action: onOpenCodex) {
                    HStack(spacing: 6) {
                        if isLaunchingCodex {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.forward.app.fill")
                        }
                        Text(isLaunchingCodex
                             ? L("正在启动 Codex", "Opening Codex")
                             : L("打开 Codex/ChatGPT", "Open Codex/ChatGPT"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange.opacity(0.72))
                .disabled(isLaunchingCodex)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.18), lineWidth: 1))
    }
}

private struct CodexAccessCard: View {
    @ObservedObject var monitor: UsageMonitor
    @EnvironmentObject private var localization: AppLocalization

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: "lock.open.display")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.cyan)

                Text(L("完成本机 Codex 授权", "Authorize local Codex access"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                InfoPopoverButton(
                    title: L("本机授权说明", "Local access authorization"),
                    sections: [
                        InfoPopoverSection(
                            icon: "app.badge.checkmark",
                            title: L("Codex 程序", "Codex app"),
                            text: L(
                                "第一步授权应用启动本机 Codex App Server，用于读取账号额度和 Token 统计。",
                                "The first permission lets the app launch the local Codex App Server to read account quota and token totals."
                            )
                        ),
                        InfoPopoverSection(
                            icon: "key.horizontal.fill",
                            title: L("登录资料", "Sign-in data"),
                            text: L(
                                "第二步授权 Codex 使用本机 .codex 登录资料。应用本身不会解析账号内容；文件选择器会自动显示隐藏的 .codex 文件夹。",
                                "The second permission lets Codex use local .codex sign-in data. This app does not parse account contents, and the file picker reveals the hidden .codex folder automatically."
                            )
                        ),
                    ]
                )
            }

            HStack(spacing: 8) {
                Button(
                    monitor.codexSelectionName == nil
                        ? L("1. 选择 Codex 程序", "1. Choose Codex app")
                        : L("✓ Codex 程序", "✓ Codex app")
                ) {
                    monitor.chooseCodexLocation()
                }
                .buttonStyle(.borderedProminent)
                .tint(monitor.codexSelectionName == nil ? .cyan.opacity(0.75) : .green.opacity(0.65))

                Button(
                    monitor.codexHomeSelectionName == nil
                        ? L("2. 授权 .codex", "2. Authorize .codex")
                        : L("✓ 登录资料", "✓ Sign-in data")
                ) {
                    monitor.chooseCodexHomeLocation()
                }
                .buttonStyle(.borderedProminent)
                .tint(monitor.codexHomeSelectionName == nil ? .cyan.opacity(0.75) : .green.opacity(0.65))
            }
        }
        .padding(12)
        .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.cyan.opacity(0.18), lineWidth: 1)
        )
    }
}
