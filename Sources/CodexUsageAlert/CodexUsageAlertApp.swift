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
        .defaultSize(width: 380, height: 780)
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
    var tint: Color { self == .codex ? .cyan : Color(red: 0.75, green: 0.60, blue: 1) }
}

private struct UsagePopover: View {
    @ObservedObject var monitor: UsageMonitor
    @State private var showingSettings = false
    @State private var selectedService: UsageService = .codex
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedPercent: Double? {
        if selectedService == .codex {
            return monitor.codexDataAvailable ? monitor.snapshot?.usedPercent : nil
        }
        return monitor.grokStatus == .ready ? monitor.grokSnapshot?.usedPercent : nil
    }
    private var selectedIncrease: Double {
        selectedService == .codex ? monitor.dailyIncrease : monitor.grokDailyIncrease
    }
    private var selectedEnabled: Bool {
        selectedService == .codex ? monitor.codexMonitoringEnabled : monitor.grokMonitoringEnabled
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.035, green: 0.075, blue: 0.16),
                                    Color(red: 0.025, green: 0.045, blue: 0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    header
                    HStack(spacing: 10) {
                        serviceCard(.codex)
                        serviceCard(.grok)
                    }
                    Picker("服务详情", selection: $selectedService) {
                        ForEach(UsageService.allCases) { service in
                            Text(service.rawValue).tag(service)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    HStack(spacing: 8) {
                        MetricRow(icon: "arrow.up.right", label: "今日增加",
                                  value: selectedPercent == nil ? "—" : "\(UsageMonitor.percent(selectedIncrease))%", tint: selectedService.tint)
                        Spacer(minLength: 0)
                        MetricRow(icon: "chart.pie.fill", label: "周期剩余",
                                  value: selectedPercent.map { "\(UsageMonitor.percent(100 - $0))%" } ?? "—", tint: selectedService.tint)
                        Spacer(minLength: 0)
                        MetricRow(icon: notificationIcon, label: "通知状态",
                                  value: selectedEnabled ? notificationSummary : "监控已关", tint: .orange)
                    }
                    if selectedPercent != nil {
                        DailyBudgetCard(dailyIncrease: selectedIncrease, statusColor: selectedService.tint)
                    } else {
                        Text(selectedEnabled ? "等待有效数据后计算今日额度预算" : "此服务的监控已关闭，可在设置中开启")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, minHeight: 70)
                            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
                    }
                    if selectedService == .codex {
                        if let tokenUsage = monitor.tokenUsage, selectedPercent != nil {
                            TokenUsageCard(usage: tokenUsage, unitStyle: monitor.tokenUnitStyle)
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
        .frame(width: 380, height: min(780, (NSScreen.main?.visibleFrame.height ?? 860) - 80))
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: showingSettings)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable().frame(width: 36, height: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("用量预警").font(.system(size: 17, weight: .semibold))
                Text(lastUpdatedText).font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 4)
            Text(monitor.overallStatus)
                .font(.system(size: 10.5, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(statusColor.opacity(0.15), in: Capsule())
                .foregroundStyle(statusColor)
        }
    }

    private func serviceCard(_ service: UsageService) -> some View {
        let enabled = service == .codex ? monitor.codexMonitoringEnabled : monitor.grokMonitoringEnabled
        let percent = service == .codex
            ? (monitor.codexDataAvailable ? monitor.snapshot?.usedPercent : nil)
            : (monitor.grokStatus == .ready ? monitor.grokSnapshot?.usedPercent : nil)
        let reset = service == .codex ? monitor.snapshot?.resetsAt : monitor.grokSnapshot?.resetAt
        let state = !enabled ? "监控已关闭" : service == .codex
            ? (monitor.errorMessage == nil ? "连接中" : "读取失败") : monitor.grokStatus.title
        return Button { selectedService = service } label: {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(service.rawValue).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if selectedService == service {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(service.tint)
                    }
                }
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 7)
                    Circle().trim(from: 0, to: (percent ?? 0) / 100)
                        .stroke(service.tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(percent.map { "\(UsageMonitor.percent($0))%" } ?? "—")
                            .font(.system(size: 23, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(percent == nil ? state : "本周期已用").font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }.frame(width: 88, height: 88).padding(.vertical, 3)
                Text(percent != nil ? reset.map { "重置 \($0.formatted(.dateTime.month().day().hour().minute()))" } ?? "重置时间未填写" : state)
                    .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
            .padding(12).frame(maxWidth: .infinity)
            .background(service.tint.opacity(selectedService == service ? 0.10 : 0.035), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(selectedService == service ? service.tint.opacity(0.65) : Color.white.opacity(0.1), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(service.rawValue)，\(percent.map { "已用 \(UsageMonitor.percent($0))%" } ?? state)")
        .accessibilityAddTraits(selectedService == service ? .isSelected : [])
    }

    private var grokUsageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("任务 / 消息用量", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(UsageService.grok.tint)
            HStack {
                TokenMetric(value: selectedPercent != nil ? monitor.grokSnapshot.map { "\($0.tasksToday)" } ?? "—" : "—", label: "今日次数", exactValue: nil)
                Divider()
                TokenMetric(value: selectedPercent != nil ? monitor.grokSnapshot.map { "\($0.tasksPeriod)" } ?? "—" : "—", label: "本周期次数", exactValue: nil)
            }.frame(height: 35)
            Text(selectedPercent != nil ? (monitor.grokSnapshot?.plan ?? "本地记录") : "在设置中手动填写，或接入本地 JSON 文件。")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
            if let updated = monitor.grokSnapshot?.updatedAt {
                Text("数据时间 \(updated.formatted(.dateTime.month().day().hour().minute()))")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
            }
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
    }

    private var sharedAlerts: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("用量预警", systemImage: "bell.badge").font(.system(size: 12, weight: .semibold))
            Text("两项服务独立计量 · 5 / 10 / 15 / 20 分级提醒")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
            if monitor.codexMonitoringEnabled, let error = monitor.errorMessage {
                Text("口袋：\(error)").font(.system(size: 10)).foregroundStyle(.orange).lineLimit(3).help(error)
            }
            if monitor.grokMonitoringEnabled, monitor.grokStatus != .ready {
                Text("Grok Bot：\(monitor.grokStatus.title) · 请更新本地文件或手动填写")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }
            if monitor.overallLevel != .normal {
                Text("\(monitor.overallLevel.title)：请留意今日用量")
                    .font(.system(size: 10)).foregroundStyle(statusColor)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
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
            Text("口袋：本机 Codex CLI · Grok Bot：本地 JSON / 手动填写")
            HStack {
                Text(monitor.refreshSummary)
                Spacer()
                Text("V\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
            }
        }.font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.65))
    }

    private var statusColor: Color {
        if monitor.overallLevel == .normal && monitor.overallStatus != "一切正常" { return .orange }
        switch monitor.overallLevel {
        case .normal: return Color(red: 0.15, green: 0.88, blue: 0.78)
        case .notice: return .yellow
        case .reminder: return .orange
        case .high, .cap: return Color(red: 1, green: 0.40, blue: 0.42)
        }
    }

    private var lastUpdatedText: String {
        if monitor.isRefreshing { return "正在刷新用量…" }
        return "口袋 + Grok Bot · 双服务监控"
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
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }
}

private struct DailyBudgetCard: View {
    let dailyIncrease: Double
    let statusColor: Color

    private let cap = 20.0

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日额度预算")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("按自然日累计，最高 20 个百分点")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Text("\(UsageMonitor.percent(dailyIncrease)) / 20%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusColor)
            }

            GeometryReader { geometry in
                let inset: CGFloat = 20
                let width = max(0, geometry.size.width - inset * 2)
                ZStack(alignment: .topLeading) {
                    Capsule().fill(Color.white.opacity(0.075))
                        .frame(width: width, height: 8).offset(x: inset)
                    Capsule().fill(statusColor)
                        .frame(width: width * min(max(dailyIncrease / cap, 0), 1), height: 8)
                        .offset(x: inset)
                    ForEach([5, 10, 15, 20], id: \.self) { threshold in
                        let x = inset + width * CGFloat(threshold) / CGFloat(cap)
                        Circle()
                            .fill(dailyIncrease >= Double(threshold) ? statusColor : Color.white.opacity(0.35))
                            .frame(width: 5, height: 5)
                            .position(x: x, y: 4)
                        Text([5: "5 注意", 10: "10 提醒", 15: "15 偏高", 20: "20 上限"][threshold] ?? "")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .fixedSize()
                            .position(x: x, y: 23)
                    }
                }
            }.frame(height: 31)
        }
        .padding(13)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.065), lineWidth: 1))
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
