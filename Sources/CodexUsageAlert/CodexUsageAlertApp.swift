import AppKit
import SwiftUI
import UsageCore

@main
struct CodexUsageAlertApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = UsageMonitor.shared

    init() {
        // A position inherited from CoMex can be outside every connected display.
        // Repair only that invalid position; preserve valid user placement.
        let defaults = UserDefaults.standard
        let key = "NSStatusItem Preferred Position Item-0"
        let position = (defaults.object(forKey: key) as? NSNumber)?.doubleValue
        if let replacement = MenuBarPlacement.replacementPosition(
            for: position,
            screenWidths: NSScreen.screens.map { Double($0.frame.width) }
        ) {
            defaults.set(replacement, forKey: key)
        }
    }

    var body: some Scene {
        WindowGroup("用量预警", id: "dashboard") {
            UsagePopover(monitor: monitor)
        }
        .defaultSize(width: 380, height: 620)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("用量预警，\(monitor.menuTitle)")
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

private enum UsageService: String, CaseIterable, Identifiable {
    case codex = "口袋"
    case grok = "Grok Bot"
    var id: String { rawValue }
    var tint: Color { self == .codex ? DashboardStyle.cyan : DashboardStyle.purple }
}

private enum DashboardStyle {
    static let backgroundTop = Color(red: 0.055, green: 0.10, blue: 0.17)
    static let backgroundBottom = Color(red: 0.035, green: 0.06, blue: 0.105)
    static let surface = Color(red: 0.062, green: 0.108, blue: 0.18)
    static let border = Color(red: 0.13, green: 0.20, blue: 0.29)
    static let secondary = Color(red: 0.60, green: 0.67, blue: 0.75)
    static let cyan = Color(red: 0.08, green: 0.77, blue: 0.83)
    static let purple = Color(red: 0.55, green: 0.46, blue: 1)
    static let selection = Color(red: 0.025, green: 0.57, blue: 0.69)
    static let mint = Color(red: 0.19, green: 0.86, blue: 0.76)
}

private struct UsagePopover: View {
    @ObservedObject var monitor: UsageMonitor
    @State private var showingSettings = false
    @State private var selectedService: UsageService = .codex
    @State private var showingTokenDetails = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func percent(for service: UsageService) -> Double? {
        service == .codex
            ? (monitor.codexDataAvailable ? monitor.snapshot?.usedPercent : nil)
            : (monitor.grokStatus == .ready ? monitor.grokSnapshot?.usedPercent : nil)
    }
    private func enabled(_ service: UsageService) -> Bool {
        service == .codex ? monitor.codexMonitoringEnabled : monitor.grokMonitoringEnabled
    }
    private func reset(for service: UsageService) -> Date? {
        service == .codex ? monitor.snapshot?.resetsAt : monitor.grokSnapshot?.resetAt
    }
    private func increase(for service: UsageService) -> Double {
        service == .codex ? monitor.dailyIncrease : monitor.grokDailyIncrease
    }
    private func state(for service: UsageService) -> String {
        if !enabled(service) { return "监控已关闭" }
        if service == .grok { return monitor.grokStatus.title }
        return monitor.errorMessage == nil ? "等待更新" : "读取失败"
    }
    private var selectedPercent: Double? { percent(for: selectedService) }
    private var selectedIncrease: Double { increase(for: selectedService) }
    private var selectedEnabled: Bool { enabled(selectedService) }
    private var attentionCount: Int {
        UsageService.allCases.filter {
            enabled($0) && (percent(for: $0) == nil || increase(for: $0) >= 5)
        }.count
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [DashboardStyle.backgroundTop, DashboardStyle.backgroundBottom],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 9) {
                    header
                    HStack(spacing: 10) {
                        serviceCard(.codex)
                        serviceCard(.grok)
                    }
                    servicePicker
                    HStack(spacing: 7) {
                        MetricRow(icon: "arrow.up.right", label: "今日增加",
                                  value: selectedPercent == nil ? "—" : "\(UsageMonitor.percent(selectedIncrease))%", tint: .white)
                        MetricRow(icon: "chart.pie", label: "周期剩余",
                                  value: selectedPercent.map { "\(UsageMonitor.percent(100 - $0))%" } ?? "—", tint: .white)
                        MetricRow(icon: notificationIcon, label: "通知状态",
                                  value: selectedEnabled ? notificationSummary : "监控已关", tint: .yellow)
                    }
                    if selectedPercent != nil {
                        DailyBudgetCard(dailyIncrease: selectedIncrease, statusColor: DashboardStyle.mint)
                    } else {
                        Text(selectedEnabled ? "等待有效数据后计算今日额度预算" : "此服务的监控已关闭，可在设置中开启")
                            .font(.system(size: 11)).foregroundStyle(DashboardStyle.secondary)
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .background(DashboardStyle.surface, in: RoundedRectangle(cornerRadius: 13))
                    }
                    if selectedService == .codex {
                        if let tokenUsage = monitor.tokenUsage, selectedPercent != nil {
                            tokenSummary(tokenUsage)
                            if showingTokenDetails {
                                TokenUsageCard(usage: tokenUsage, unitStyle: monitor.tokenUnitStyle)
                            }
                        } else {
                            TokenUsageUnavailableCard(isRefreshing: monitor.isRefreshing, errorMessage: monitor.tokenUsageErrorMessage)
                        }
                    } else {
                        grokUsageCard
                    }
                    sharedAlerts
                    controls
                    footer
                }
                .padding(18)
            }
            .foregroundStyle(.white)
            .accessibilityHidden(showingSettings)
            if showingSettings {
                Color.black.opacity(0.6).ignoresSafeArea()
                RefreshSettingsView(monitor: monitor) { showingSettings = false }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.16), lineWidth: 1))
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }
        }
        .frame(width: 380, height: min(620, (NSScreen.main?.visibleFrame.height ?? 860) - 80))
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: showingSettings)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable().frame(width: 36, height: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("用量预警").font(.system(size: 17, weight: .bold))
                    Spacer(minLength: 4)
                    Label(attentionCount > 0 ? "\(attentionCount) 项注意" : monitor.overallStatus,
                          systemImage: "circle.fill")
                        .font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(statusColor.opacity(0.14), in: Capsule())
                        .overlay(Capsule().stroke(statusColor.opacity(0.6), lineWidth: 1))
                        .foregroundStyle(statusColor)
                }
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(lastUpdatedText(at: context.date))
                        .font(.system(size: 10.5)).foregroundStyle(DashboardStyle.secondary)
                }
            }
        }
        .padding(.bottom, 5)
    }

    private var servicePicker: some View {
        HStack(spacing: 0) {
            ForEach(UsageService.allCases) { service in
                Button { selectedService = service } label: {
                    Text(service.rawValue)
                        .font(.system(size: 13, weight: selectedService == service ? .semibold : .regular))
                        .foregroundStyle(selectedService == service ? .white : DashboardStyle.secondary)
                        .frame(maxWidth: .infinity, minHeight: 29)
                        .background(selectedService == service ? DashboardStyle.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看\(service.rawValue)详情")
                .accessibilityAddTraits(selectedService == service ? .isSelected : [])
            }
        }
        .padding(3)
        .background(DashboardStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("服务详情")
    }

    private func serviceCard(_ service: UsageService) -> some View {
        let percent = percent(for: service)
        let resetText = percent == nil ? state(for: service) : reset(for: service).map {
            service == .codex
                ? $0.formatted(.dateTime.month().day().hour(.twoDigits(amPM: .omitted)).minute()) + " 重置"
                : $0.formatted(.dateTime.month().day()) + " 重置"
        } ?? "重置时间未填写"
        return Button { selectedService = service } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(DashboardStyle.border.opacity(0.7), lineWidth: 6)
                    Circle().trim(from: 0, to: (percent ?? 0) / 100)
                        .stroke(service.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(percent.map { "\(UsageMonitor.percent($0))%" } ?? "—")
                        .font(.system(size: 15, weight: .bold)).monospacedDigit()
                        .minimumScaleFactor(0.8).lineLimit(1)
                        .padding(.horizontal, 2)
                }.frame(width: 51, height: 51)
                VStack(alignment: .leading, spacing: 3) {
                    Text(service.rawValue).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    Text(percent == nil ? state(for: service) : "本周期已用")
                        .font(.system(size: 10)).foregroundStyle(DashboardStyle.secondary)
                    Label(resetText, systemImage: "arrow.clockwise")
                        .font(.system(size: 9.5)).foregroundStyle(DashboardStyle.cyan)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 78)
            .background(DashboardStyle.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(
                selectedService == service ? DashboardStyle.cyan : DashboardStyle.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(service.rawValue)，\(percent.map { "已用 \(UsageMonitor.percent($0))%" } ?? state(for: service))，\(resetText)")
        .accessibilityAddTraits(selectedService == service ? .isSelected : [])
    }

    private func tokenSummary(_ usage: AccountTokenUsage) -> some View {
        let today = usage.dailyUsageBuckets.first { $0.startDate == UsageMonitor.dayKey(for: Date()) }
        let todayText = today.map { TokenCountFormatter.compact($0.tokens, style: monitor.tokenUnitStyle) } ?? "待更新"
        return Button { showingTokenDetails.toggle() } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label("Token 使用量", systemImage: "number").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: showingTokenDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9)).foregroundStyle(DashboardStyle.secondary)
                }
                Text("今日 \(todayText) · 本月 \(TokenCountFormatter.compact(usage.monthToDateTokens(), style: monitor.tokenUnitStyle))")
                    .font(.system(size: 10.5)).foregroundStyle(DashboardStyle.secondary)
            }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(DashboardStyle.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(DashboardStyle.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(showingTokenDetails ? "收起 Token 趋势详情" : "展开 Token 趋势详情；本月统计与额度周期独立")
        .accessibilityValue(showingTokenDetails ? "已展开" : "已收起")
    }

    private var grokUsageCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("任务 / 消息用量", systemImage: "diamond.fill")
                .font(.system(size: 13, weight: .semibold))
            if selectedPercent != nil, let usage = monitor.grokSnapshot {
                Text("今日 \(usage.tasksToday) 次 · 本周期 \(usage.tasksPeriod) 次")
                    .font(.system(size: 10.5)).foregroundStyle(DashboardStyle.secondary)
            } else {
                Text("在设置中手动填写，或接入本地 JSON 文件。")
                    .font(.system(size: 10.5)).foregroundStyle(DashboardStyle.secondary)
            }
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(DashboardStyle.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(DashboardStyle.border, lineWidth: 1))
            .help(monitor.grokSnapshot.map { "套餐：\($0.plan)；数据时间：\($0.updatedAt.formatted())" } ?? "等待本地用量记录")
    }

    private var sharedAlerts: some View {
        VStack(spacing: 7) {
            serviceAlert(.codex)
            serviceAlert(.grok)
        }
    }

    private func serviceAlert(_ service: UsageService) -> some View {
        let needsAttention = enabled(service) && (percent(for: service) == nil || increase(for: service) >= 5)
        let tint: Color = !enabled(service) ? DashboardStyle.secondary : needsAttention ? .orange : DashboardStyle.mint
        return Label(alertText(for: service), systemImage: !enabled(service) ? "pause.circle" : needsAttention ? "exclamationmark.triangle.fill" : "checkmark")
            .font(.system(size: 10.5))
            .foregroundStyle(needsAttention ? .white : tint)
            .padding(.horizontal, 11).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.35), lineWidth: 1))
            .help(service == .codex ? monitor.errorMessage ?? "按今日增加的 5 / 10 / 15 / 20 个百分点独立提醒" : "读取本地 JSON；超过 24 小时的数据不参与预警")
    }

    private func alertText(for service: UsageService) -> String {
        let name = service.rawValue
        guard enabled(service) else { return "\(name) 监控已关闭，可在设置中开启" }
        guard let used = percent(for: service) else {
            return "\(name)：\(state(for: service)) · \(service == .codex ? "请刷新或检查登录状态" : "请更新文件或手动填写")"
        }
        if increase(for: service) >= 5 {
            return "\(name) 本周期已用 \(UsageMonitor.percent(used))%，今日增加 \(UsageMonitor.percent(increase(for: service)))%"
        }
        guard let date = reset(for: service) else { return "\(name) 用量正常" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                   to: Calendar.current.startOfDay(for: date)).day ?? 0
        if date <= Date() { return "\(name) 已到重置时间，等待用量更新" }
        return days > 0 ? "\(name) 用量正常，距重置还有 \(days) 天" : "\(name) 用量正常，今天重置"
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
                .buttonStyle(DashboardActionStyle(fill: DashboardStyle.selection))
                .disabled(monitor.isRefreshing)

                Button {
                    monitor.sendTestNotification()
                } label: {
                    Label("测试通知", systemImage: "bell.fill")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(DashboardActionStyle(fill: Color(red: 0.22, green: 0.25, blue: 0.29)))
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
                .help("监控与通知设置")
                .accessibilityLabel("监控与通知设置")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.62))
                .help("退出应用")
                .accessibilityLabel("退出应用")
            }
            .padding(.horizontal, 3)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("口袋：本机 codex app-server · Grok Bot：本地 JSON / 手动填写")
            HStack {
                Text("V\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                Spacer()
                Text(monitor.refreshSummary)
            }
        }.font(.system(size: 9.5)).foregroundStyle(DashboardStyle.secondary)
    }

    private var statusColor: Color {
        if attentionCount > 0 && monitor.overallLevel == .normal { return .orange }
        switch monitor.overallLevel {
        case .normal: return Color(red: 0.15, green: 0.88, blue: 0.78)
        case .notice: return .yellow
        case .reminder: return .orange
        case .high, .cap: return Color(red: 1, green: 0.40, blue: 0.42)
        }
    }

    private func lastUpdatedText(at now: Date) -> String {
        if monitor.isRefreshing { return "监控 口袋 + Grok Bot · 正在刷新…" }
        let dates = [monitor.codexDataAvailable ? monitor.snapshot?.fetchedAt : nil,
                     monitor.grokStatus == .ready ? monitor.grokSnapshot?.updatedAt : nil].compactMap { $0 }
        guard let date = dates.max() else { return "监控 口袋 + Grok Bot · 等待数据" }
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        let age = minutes == 0 ? "刚刚更新" : minutes < 60 ? "\(minutes) 分钟前更新" : "\(minutes / 60) 小时前更新"
        return "监控 口袋 + Grok Bot · \(age)"
    }

    private var notificationSummary: String {
        let normalized = monitor.notificationStatus.lowercased()
        if normalized.contains("not allowed") || normalized.contains("denied") {
            return "未允许"
        }
        switch monitor.notificationStatus {
        case "已允许", "已发送": return "已允许"
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
    @State private var codexEnabled: Bool
    @State private var grokEnabled: Bool
    @State private var manualPercent = ""
    @State private var manualResetAt: Date
    @State private var manualError: String?
    @State private var manualSaved = false

    init(monitor: UsageMonitor, onDone: @escaping () -> Void) {
        self.monitor = monitor
        self.onDone = onDone
        _selectedSchedule = State(initialValue: monitor.refreshSchedule)
        _selectedDailyRefreshTime = State(initialValue: monitor.dailyRefreshTime)
        _selectedTokenUnitStyle = State(initialValue: monitor.tokenUnitStyle)
        _codexEnabled = State(initialValue: monitor.codexMonitoringEnabled)
        _grokEnabled = State(initialValue: monitor.grokMonitoringEnabled)
        _manualResetAt = State(initialValue: monitor.grokSnapshot?.resetAt ?? Date())
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
                        Text("监控与通知设置")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("独立管理口袋与 Grok Bot 的用量提醒")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.65))
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

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("监控口袋（Codex）", isOn: $codexEnabled)
                    Toggle("监控 Grok Bot", isOn: $grokEnabled)
                }.toggleStyle(.switch).tint(.cyan).font(.system(size: 12))

                VStack(alignment: .leading, spacing: 7) {
                    Text("Grok Bot 手动填写已用百分比").font(.system(size: 12, weight: .medium))
                    HStack {
                        TextField("0–100", text: $manualPercent)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Grok Bot 已用百分比")
                            .onChange(of: manualPercent) { _ in manualSaved = false; manualError = nil }
                        Text("%")
                        Button("保存数值") { saveManual() }
                    }
                    DatePicker("周期重置时间", selection: $manualResetAt)
                        .font(.system(size: 11))
                    Text(manualSaved ? "已保存，数据有效期 24 小时" : "写入本地文件；首次记录作为今日基线。")
                        .font(.system(size: 10)).foregroundStyle(manualSaved ? .green : .white.opacity(0.7))
                    if let manualError {
                        Text(manualError).font(.system(size: 10)).foregroundStyle(.orange)
                    }
                }
                Divider()
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

    private func saveManual() {
        guard let percent = Double(manualPercent), percent.isFinite, (0...100).contains(percent) else {
            manualError = "请输入 0 到 100 之间的数字"
            return
        }
        do {
            try monitor.saveManualGrokUsage(percent: percent, resetAt: manualResetAt)
            manualError = nil
            manualSaved = true
        } catch {
            manualError = "保存失败：\(error.localizedDescription)"
        }
    }

    private func saveAndClose() {
        monitor.setMonitoring(codex: codexEnabled, grok: grokEnabled)
        monitor.applySettings(
            refreshSchedule: selectedSchedule,
            dailyRefreshTime: selectedDailyRefreshTime,
            tokenUnitStyle: selectedTokenUnitStyle
        )
        onDone()
    }
}

private struct DashboardActionStyle: ButtonStyle {
    let fill: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .frame(minHeight: 34)
            .background(fill, in: RoundedRectangle(cornerRadius: 13))
            .opacity(!isEnabled ? 0.55 : configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 13))
    }
}

private struct MetricRow: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true)
                Text(value).monospacedDigit()
            }
            .font(.system(size: 16, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.8)
            Text(label).font(.system(size: 10)).foregroundStyle(DashboardStyle.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 10)
        .background(DashboardStyle.surface, in: RoundedRectangle(cornerRadius: 13))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)，\(value)")
    }
}

private struct DailyBudgetCard: View {
    let dailyIncrease: Double
    let statusColor: Color
    private let cap = 20.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日额度预算").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(UsageMonitor.percent(dailyIncrease)) / 20%")
                    .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(statusColor)
            }
            VStack(spacing: 5) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DashboardStyle.border)
                        Capsule().fill(LinearGradient(colors: [DashboardStyle.cyan, statusColor],
                                                      startPoint: .leading, endPoint: .trailing))
                            .frame(width: geometry.size.width * min(max(dailyIncrease / cap, 0), 1))
                    }
                }.frame(height: 6)
                HStack {
                    Text("5 注意")
                    Spacer()
                    Text("10 提醒")
                    Spacer()
                    Text("15 偏高")
                    Spacer()
                    Text("20 上限")
                }.font(.system(size: 9)).foregroundStyle(DashboardStyle.secondary)
            }
        }
        .padding(13)
        .background(DashboardStyle.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(DashboardStyle.border, lineWidth: 1))
        .help("按自然日累计今日增加的额度百分点，最高 20 个百分点；标注为四档预警级别。")
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
                    .font(.system(size: 9.5, weight: .medium))
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
                .foregroundStyle(.white.opacity(0.65))
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
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.65))
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
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.65))
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
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
        }
        .padding(13)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .help(errorMessage ?? "等待 Codex 返回 Token 数据")
    }
}
