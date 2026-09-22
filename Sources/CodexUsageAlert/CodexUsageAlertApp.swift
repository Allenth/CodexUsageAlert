import AppKit
import SwiftUI
import UsageCore

@main
struct CodexUsageAlertApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = UsageMonitor.shared

    var body: some Scene {
        WindowGroup("Codex 用量预警", id: "dashboard") {
            UsagePopover(monitor: monitor)
        }
        .defaultSize(width: 380, height: 750)
        .windowResizability(.contentSize)

        MenuBarExtra {
            UsagePopover(monitor: monitor)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: MenuBarIcon.image)
                    .frame(width: 16, height: 16)
                Text(monitor.menuTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }

            if let context = NSGraphicsContext.current?.cgContext,
               let gradient = CGGradient(
                   colorsSpace: CGColorSpaceCreateDeviceRGB(),
                   colors: [
                       NSColor(
                           calibratedRed: 0.12,
                           green: 0.92,
                           blue: 0.90,
                           alpha: 1
                       ).cgColor,
                       NSColor(
                           calibratedRed: 0.08,
                           green: 0.48,
                           blue: 1.00,
                           alpha: 1
                       ).cgColor,
                   ] as CFArray,
                   locations: [0, 1]
               ) {
                context.setLineWidth(2.2)
                context.setLineCap(.round)
                context.addArc(
                    center: CGPoint(x: 7.7, y: 7.7),
                    radius: 5.4,
                    startAngle: 42 * .pi / 180,
                    endAngle: 318 * .pi / 180,
                    clockwise: false
                )
                context.replacePathWithStrokedPath()
                context.clip()
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 2, y: 3),
                    end: CGPoint(x: 13, y: 13),
                    options: []
                )
            }

            NSColor(
                calibratedRed: 1.00,
                green: 0.66,
                blue: 0.12,
                alpha: 1
            ).setFill()
            NSBezierPath(
                ovalIn: NSRect(x: 11.8, y: 11.8, width: 2.2, height: 2.2)
            )
            .fill()
            return true
        }
        image.isTemplate = false
        return image
    }()
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            self.showDashboard(NSApplication.shared)
        }
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
        application.activate(ignoringOtherApps: true)
        if let window = application.windows.first(where: { $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

private struct UsagePopover: View {
    @ObservedObject var monitor: UsageMonitor
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

                HStack(spacing: 24) {
                    UsageGauge(
                        usedPercent: monitor.snapshot?.usedPercent ?? 0,
                        color: statusColor,
                        isRefreshing: monitor.isRefreshing
                    )

                    VStack(alignment: .leading, spacing: 13) {
                        MetricRow(
                            icon: "arrow.up.right",
                            label: "今日增加",
                            value: "\(UsageMonitor.percent(monitor.dailyIncrease))%",
                            tint: statusColor
                        )
                        MetricRow(
                            icon: "chart.pie.fill",
                            label: "周期剩余",
                            value: "\(UsageMonitor.percent(monitor.snapshot?.remainingPercent ?? 100))%",
                            tint: .cyan
                        )
                        MetricRow(
                            icon: notificationIcon,
                            label: "通知状态",
                            value: notificationSummary,
                            tint: .orange
                        )
                    }
                }

                DailyBudgetCard(
                    dailyIncrease: monitor.dailyIncrease,
                    statusColor: statusColor,
                    budget: monitor.rolloverBudget
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
                            value: snapshot.resetsAt.formatted(.dateTime.month().day()),
                            detail: snapshot.resetsAt.formatted(.dateTime.hour().minute()),
                            label: "下次重置"
                        )
                        StatTile(
                            icon: "clock.arrow.circlepath",
                            value: "\(UsageMonitor.percent(snapshot.windowDays)) 天",
                            detail: "滚动额度",
                            label: "额度周期"
                        )
                        StatTile(
                            icon: "bell.badge.fill",
                            value: "5 · 10 · 15",
                            detail: "20% 为上限",
                            label: "预警刻度"
                        )
                    }
                }

                if let error = monitor.errorMessage {
                    ErrorBanner(message: error)
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
                Text("Codex 用量预警")
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
                Text(monitor.level.title)
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
                        Text(monitor.isRefreshing ? "正在读取" : "立即刷新")
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
                    Label("测试通知", systemImage: "bell.fill")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.white.opacity(0.12))
                .controlSize(.large)
            }

            HStack {
                Toggle(
                    "登录时自动启动",
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

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.62))
                .help("刷新与通知设置")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.62))
                .help("退出应用")
            }
            .padding(.horizontal, 3)
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.shield.fill")
            Text("数据仅从本机 Codex CLI 读取")
            Spacer()
            Text(monitor.refreshSummary)
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
        guard let date = monitor.snapshot?.fetchedAt else { return "正在连接本机 Codex…" }
        return "更新于 \(date.formatted(.dateTime.hour().minute()))"
    }

    private var notificationSummary: String {
        let normalized = monitor.notificationStatus.lowercased()
        if normalized.contains("not allowed") || normalized.contains("denied") {
            return "未允许"
        }
        switch monitor.notificationStatus {
        case "已允许", "已发送": return "已开启"
        case "未允许": return "未允许"
        default: return monitor.notificationStatus.count > 8 ? "需检查" : monitor.notificationStatus
        }
    }

    private var notificationIcon: String {
        notificationSummary == "未允许" ? "bell.slash.fill" : "bell.fill"
    }
}

private struct RefreshSettingsView: View {
    @ObservedObject var monitor: UsageMonitor
    let onDone: () -> Void

    @State private var selectedSchedule: RefreshSchedule
    @State private var selectedDailyRefreshTime: Date
    @State private var selectedTokenUnitStyle: TokenUnitStyle

    init(monitor: UsageMonitor, onDone: @escaping () -> Void) {
        self.monitor = monitor
        self.onDone = onDone
        _selectedSchedule = State(initialValue: monitor.refreshSchedule)
        _selectedDailyRefreshTime = State(initialValue: monitor.dailyRefreshTime)
        _selectedTokenUnitStyle = State(initialValue: monitor.tokenUnitStyle)
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
                        Text("自动刷新设置")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("默认每 15 分钟，也可改为每天固定时间")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    Spacer()
                    Button {
                        saveAndClose()
                    } label: {
                        Text("完成")
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.horizontal, 4)
                    }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.00, green: 0.58, blue: 0.72))
                        .keyboardShortcut(.defaultAction)
                }

                Picker(
                    "刷新频率",
                    selection: $selectedSchedule
                ) {
                    ForEach(RefreshSchedule.allCases) { schedule in
                        Text(schedule.title).tag(schedule)
                    }
                }
                .pickerStyle(.radioGroup)
                .foregroundStyle(.white)

                if selectedSchedule == .daily {
                    HStack {
                        Label("每天刷新时间", systemImage: "calendar.badge.clock")
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
                    Text("Token 数量单位")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))

                    Picker(
                        "Token 数量单位",
                        selection: $selectedTokenUnitStyle
                    ) {
                        ForEach(TokenUnitStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                Divider().overlay(Color.white.opacity(0.08))

                Button {
                    monitor.openNotificationSettings()
                } label: {
                    HStack {
                        Label("打开 macOS 通知设置", systemImage: "bell.badge.fill")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .foregroundStyle(.white.opacity(0.82))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .frame(width: 330)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }

    private func saveAndClose() {
        monitor.applySettings(
            refreshSchedule: selectedSchedule,
            dailyRefreshTime: selectedDailyRefreshTime,
            tokenUnitStyle: selectedTokenUnitStyle
        )
        onDone()
    }
}

private struct UsageGauge: View {
    let usedPercent: Double
    let color: Color
    let isRefreshing: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 13)

            Circle()
                .trim(from: 0, to: max(0.012, min(usedPercent / 100, 1)))
                .stroke(
                    AngularGradient(
                        colors: [.cyan, Color(red: 0.14, green: 0.68, blue: 1.0), color],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.42), radius: 7)
                .animation(.easeOut(duration: 0.5), value: usedPercent)

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(UsageMonitor.percent(usedPercent))
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Text("本周期已用")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
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
            }
        }
    }
}

private struct DailyBudgetCard: View {
    let dailyIncrease: Double
    let statusColor: Color
    let budget: DailyBudgetRollover?

    private var cap: Double {
        max(1, budget?.todayAvailablePercent ?? 20)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日可用日均预算")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(
                        budget?.hasYesterdayData == true
                            ? "昨天未用完的额度已结转"
                            : "有完整昨日快照后自动结转"
                    )
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.42))
                }
                Spacer()
                Text(
                    "\(UsageMonitor.percent(dailyIncrease)) / \(UsageMonitor.percent(cap))%"
                )
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 0) {
                BudgetInputValue(
                    value: formatted(budget?.baseDailyBudgetPercent),
                    label: "基础日均"
                )
                BudgetInputValue(
                    value: formatted(budget?.yesterdayAvailablePercent),
                    label: "昨日可用"
                )
                BudgetInputValue(
                    value: formatted(budget?.yesterdayUsedPercent),
                    label: "昨日已用"
                )
                BudgetInputValue(
                    value: "+\(formatted(budget?.carriedPercent))",
                    label: "结转"
                )
                BudgetInputValue(
                    value: formatted(budget?.todayAvailablePercent),
                    label: "今日可用"
                )
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
                }
                .frame(height: 8)
            }
            .frame(height: 8)

            HStack(spacing: 5) {
                Image(systemName: "externaldrive.badge.icloud")
                Text(sourceDescription)
            }
            .font(.system(size: 8.2))
            .foregroundStyle(.white.opacity(0.34))
        }
        .padding(13)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.065), lineWidth: 1))
    }

    private var sourceDescription: String {
        let windowDays = UsageMonitor.percent(100 / max(budget?.baseDailyBudgetPercent ?? 100, 0.1))
        if budget?.hasYesterdayData == true {
            let sourceDay = budget?.sourceDay ?? "昨日"
            return "日均：App Server 100÷\(windowDays)天 · \(sourceDay)：本机快照估算"
        }
        return "日均：App Server 100÷\(windowDays)天 · 昨日：暂无快照"
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(UsageMonitor.percent(value))%"
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

    private var recentBuckets: [DailyTokenUsage] {
        Array(usage.dailyUsageBuckets.suffix(7))
    }

    private var maximumTokens: Double {
        Double(max(recentBuckets.map(\.tokens).max() ?? 0, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "number.circle.fill")
                        .foregroundStyle(.cyan)
                    Text("Token 使用量")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                Text(
                    "总累计 \(TokenCountFormatter.compact(usage.summary.lifetimeTokens, style: unitStyle))"
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
                        usage.monthToDateTokens(),
                        style: unitStyle
                    ),
                    label: "本月截至今日",
                    exactValue: usage.monthToDateTokens()
                )
                Divider().overlay(Color.white.opacity(0.08))
                TokenMetric(
                    value: TokenCountFormatter.compact(
                        usage.peakDailyTokensThisMonth(),
                        style: unitStyle
                    ),
                    label: "本月单日峰值",
                    exactValue: usage.peakDailyTokensThisMonth()
                )
                Divider().overlay(Color.white.opacity(0.08))
                TokenMetric(
                    value: usage.summary.currentStreakDays.map { "\($0) 天" } ?? "--",
                    label: streakLabel,
                    exactValue: nil
                )
            }
            .frame(height: 35)

            if recentBuckets.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis")
                    Text("暂时没有每日 Token 趋势数据")
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.42))
                .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                GeometryReader { geometry in
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
                                            (geometry.size.height - 17)
                                                * CGFloat(Double(bucket.tokens) / maximumTokens)
                                        )
                                    )
                                    .shadow(color: .cyan.opacity(0.22), radius: 3)
                                Text(shortDate(bucket.startDate))
                                    .font(.system(size: 7.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            .frame(maxWidth: .infinity)
                            .help("\(bucket.startDate)：\(bucket.tokens.formatted()) Token")
                        }
                    }
                }
                .frame(height: 55)
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.cyan.opacity(0.12), lineWidth: 1))
    }

    private var streakLabel: String {
        guard let longest = usage.summary.longestStreakDays else { return "连续使用" }
        return "连续 · 最长 \(longest) 天"
    }

    private func shortDate(_ value: String) -> String {
        let components = value.split(separator: "-")
        guard components.count == 3 else { return value }
        return "\(components[1])/\(components[2])"
    }
}

private struct TokenMetric: View {
    let value: String
    let label: String
    let exactValue: Int64?

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
        .help(exactValue.map { "精确值：\($0.formatted()) Token" } ?? label)
    }
}

private struct TokenUsageUnavailableCard: View {
    let isRefreshing: Bool
    let errorMessage: String?

    var body: some View {
        HStack(spacing: 9) {
            if isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "number.circle")
                    .foregroundStyle(.cyan)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Token 使用量")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text(isRefreshing ? "正在读取 Token 数据…" : "Token 数据暂不可用")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.42))
            }
            Spacer()
        }
        .padding(13)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .help(errorMessage ?? "等待 Codex 返回 Token 数据")
    }
}

private struct StatTile: View {
    let icon: String
    let value: String
    let detail: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.cyan.opacity(0.85))
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

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 10.5))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white.opacity(0.86))
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.18), lineWidth: 1))
    }
}
