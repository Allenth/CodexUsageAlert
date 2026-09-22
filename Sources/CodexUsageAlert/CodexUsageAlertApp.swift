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
        .defaultSize(width: 380, height: 820)
        .windowResizability(.contentSize)

        MenuBarExtra {
            UsagePopover(monitor: monitor)
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
                            label: "本机今日增量",
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
                            detail: "20% 基础上限",
                            label: "预警刻度"
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
            Text("额度来自 Codex 服务端 · 日增量本机计算")
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Codex 数据来源")
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
                        Button("选择…") {
                            monitor.chooseCodexLocation()
                        }
                        .buttonStyle(.bordered)

                        if monitor.codexSelectionName != nil {
                            Button("恢复自动") {
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
                    Text("Codex 登录资料")
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
                            Text("只授权给本机 Codex 读取，本应用不解析账号内容")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.42))
                        }
                        Spacer()
                        Button("授权…") {
                            monitor.chooseCodexHomeLocation()
                        }
                        .buttonStyle(.bordered)

                        if monitor.codexHomeSelectionName != nil {
                            Button("移除") {
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
                    Text("今日额度预算")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("按本机快照差值累计，基础上限 20 个百分点")
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

                    ForEach([5.0, 10.0, 15.0, 20.0], id: \.self) { threshold in
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
                RuleLabel(value: "5", label: "注意")
                RuleLabel(value: "10", label: "提醒")
                RuleLabel(value: "15", label: "偏高")
                RuleLabel(value: "20", label: "基础上限")
            }

            Divider().overlay(Color.white.opacity(0.07))

            HStack(spacing: 0) {
                BudgetInputValue(
                    value: formatted(budget?.sustainableDailyBudgetPercent),
                    label: "周日均"
                )
                BudgetInputValue(
                    value: yesterdayUsedValue,
                    label: budget?.yesterdayUsageSource == .windowBaselineEstimate
                        ? "昨日估算"
                        : "昨日已用"
                )
                BudgetInputValue(
                    value: "+\(formatted(budget?.carriedPercent))",
                    label: "昨日余量"
                )
                BudgetInputValue(
                    value: formatted(budget?.baseDailyCapPercent ?? 20),
                    label: "基础上限"
                )
                BudgetInputValue(
                    value: formatted(budget?.todayAvailablePercent ?? 20),
                    label: "今日上限"
                )
            }

            Text(formulaDescription)
                .font(.system(size: 8.2, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)

            if let budget, !budget.hasYesterdayData {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                        .foregroundStyle(.orange.opacity(0.9))
                    Text(
                        "此设备从首次刷新开始记录，无法回溯其他电脑或首次刷新前的今日增量；周期已用与剩余仍来自账号实时数据。"
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 8.2))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 5) {
                Image(systemName: "info.circle.fill")
                    .help(sourceHelp)
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
        guard let budget else {
            return "周日均：等待 App Server · 昨日：暂无本机快照 · 20%：个人规则"
        }
        if budget.hasYesterdayData {
            let sourceDay = budget.sourceDay ?? "昨日"
            if budget.yesterdayUsageSource == .windowBaselineEstimate {
                return "周日均：App Server · \(sourceDay)：窗口基线估算 · 20%：个人规则"
            }
            return "周日均：App Server · \(sourceDay)：本机日快照 · 20%：个人规则"
        }
        return "周日均：App Server · 昨日：暂无本机快照 · 20%：个人规则"
    }

    private var formulaDescription: String {
        guard let budget, budget.hasYesterdayData else {
            return "今日上限 20%；此设备取得完整昨日快照后，再加上昨日日均未用部分。"
        }
        return "今日上限 = \(formatted(budget.baseDailyCapPercent)) + \(formatted(budget.carriedPercent)) = \(formatted(budget.todayAvailablePercent))"
    }

    private var sourceHelp: String {
        if budget?.yesterdayUsageSource == .windowBaselineEstimate {
            return "周日均来自 account/rateLimits/read（100 ÷ 窗口天数）。当前额度窗口从昨日开始，因此用今天首次快照的周累计基线估算昨日已用；该估算可能包含今天首次快照前的用量。20% 是你的个人规则。"
        }
        return "周日均来自 account/rateLimits/read（100 ÷ 窗口天数）；昨日已用来自本机同日额度快照差值；20% 是你的个人每日基础上限，不是 OpenAI 官方硬限制。缺少昨日快照时不按 0 计算，也不结转。"
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

    private var recentBuckets: [DailyTokenUsage] {
        Array(usage.dailyUsageBuckets.suffix(7))
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

    private var isTodayBucketMissing: Bool {
        guard let latestUsageDate else { return false }
        return latestUsageDate < todayKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "number.circle.fill")
                        .foregroundStyle(.cyan)
                    Text("账号 Token 使用量")
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
                    label: monthToDateLabel,
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

            if isTodayBucketMissing, let latestUsageDate {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark.fill")
                        .foregroundStyle(.orange.opacity(0.9))
                    Text(
                        "服务端日桶截至 \(shortDate(latestUsageDate))；本地北京时间为 \(shortDate(todayKey))。官方未声明 startDate 时区，暂不换算，也不把本地今天补为 0。"
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 8.2))
                .foregroundStyle(.white.opacity(0.52))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .help(
                    "数据源：Codex App Server account/usage/read。dailyUsageBuckets.startDate 原值为 \(latestUsageDate)，本机北京时间日期为 \(todayKey)。OpenAI 文档仅将其定义为每日分桶日期，未指定时区。"
                )
            }

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

    private var monthToDateLabel: String {
        guard let latestUsageDate else { return "本月暂无日汇总" }
        if latestUsageDate == todayKey { return "本月截至今日" }
        return "本月·服务端至 \(shortDate(latestUsageDate))"
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
                Text("账号 Token 使用量")
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
    let canOpenCodex: Bool
    let isLaunchingCodex: Bool
    let onOpenCodex: () -> Void

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
                    Text("首次使用另一台电脑时，请先启动 Codex/ChatGPT 并确认账号已登录。")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }

            if canOpenCodex {
                Button(action: onOpenCodex) {
                    HStack(spacing: 6) {
                        if isLaunchingCodex {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.forward.app.fill")
                        }
                        Text(isLaunchingCodex ? "正在启动 Codex" : "打开 Codex/ChatGPT")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: "lock.open.display")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.cyan)

                VStack(alignment: .leading, spacing: 2) {
                    Text("完成本机 Codex 授权")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("App Store 沙盒需要分别读取程序和登录资料。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            HStack(spacing: 8) {
                Button(monitor.codexSelectionName == nil ? "1. 选择 Codex 程序" : "✓ Codex 程序") {
                    monitor.chooseCodexLocation()
                }
                .buttonStyle(.borderedProminent)
                .tint(monitor.codexSelectionName == nil ? .cyan.opacity(0.75) : .green.opacity(0.65))

                Button(monitor.codexHomeSelectionName == nil ? "2. 授权登录资料" : "✓ 登录资料") {
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
