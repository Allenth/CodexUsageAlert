import Foundation
import Darwin
import OSLog

public enum CodexUsageClientError: LocalizedError {
    case executableNotFound
    case invalidExecutablePath
    case launchFailed
    case serverExited
    case timedOut
    case authenticationRequired
    case invalidResponse(String)
    case serverError(String)
    case retryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "未找到 Codex CLI。请安装 Codex，或在设置中填写 CLI 完整路径。"
        case .invalidExecutablePath:
            return "设置中的 Codex CLI 路径不存在或不可执行。请检查完整路径，或留空以自动查找。"
        case .launchFailed:
            return "无法启动 Codex CLI。请检查设置中的路径、文件权限及安装是否完整。"
        case .serverExited:
            return "Codex App Server 在返回用量前退出。请检查 Codex 安装后刷新。"
        case .timedOut:
            return "读取 Codex 用量超时。请检查网络连接后刷新。"
        case .authenticationRequired:
            return "Codex 登录已失效或尚未登录。请在当前 Codex CLI 中运行 codex login，使用 ChatGPT 账号登录后刷新。"
        case .invalidResponse(let detail):
            return "Codex 返回了无法识别的数据：\(detail)"
        case .serverError(let detail):
            return "Codex App Server 错误：\(detail)"
        case .retryFailed(let detail):
            return "\(detail)（已自动重试 1 次）"
        }
    }

    var shouldRetry: Bool {
        switch self {
        case .serverExited, .timedOut, .authenticationRequired, .serverError: return true
        default: return false
        }
    }

    public var diagnosticCode: String {
        switch self {
        case .executableNotFound: return "executable_not_found"
        case .invalidExecutablePath: return "invalid_executable_path"
        case .launchFailed: return "launch_failed"
        case .serverExited: return "server_exited"
        case .timedOut: return "timed_out"
        case .authenticationRequired: return "authentication_required"
        case .invalidResponse: return "invalid_response"
        case .serverError: return "server_error"
        case .retryFailed: return "retry_failed"
        }
    }

    static func fromServerMessage(_ message: String, code: Int? = nil) -> CodexUsageClientError {
        let lower = message.lowercased()
        if code == 401 || code == 403 || ["unauthorized", "not authenticated", "not logged in",
            "authentication", "please log in", "please login", "login required", "requires chatgpt",
            "requires codex", "sign in", "401", "token expired", "token has expired", "refresh token",
            "refresh_token"].contains(where: lower.contains) {
            return .authenticationRequired
        }
        if lower.contains("timed out") || lower.contains("timeout") { return .timedOut }
        return .serverError(String(message.prefix(400)))
    }
}

public struct CodexAppServerClient: Sendable {
    public let executableURL: URL
    public let timeout: TimeInterval
    private static let logger = Logger(subsystem: "com.huijing.codex-usage-alert", category: "CodexAppServer")

    public init(executableURL: URL? = nil, customPath: String? = nil, timeout: TimeInterval = 15) throws {
        guard let resolved = executableURL ?? Self.resolveExecutable(customPath: customPath) else {
            if !(customPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                throw CodexUsageClientError.invalidExecutablePath
            }
            throw CodexUsageClientError.executableNotFound
        }
        self.executableURL = resolved
        self.timeout = max(0.01, timeout)
    }

    public static func resolveExecutable(customPath: String? = nil) -> URL? {
        CodexExecutableResolver.resolve(customPath: customPath)
    }

    public func fetchSnapshot() throws -> UsageSnapshot {
        try fetchDashboardSnapshot().quota
    }

    public func fetchDashboardSnapshot() throws -> UsageDashboardSnapshot {
        var partial: UsageDashboardSnapshot?
        for attempt in 0...1 {
            do {
                let (dashboard, tokenError) = try fetchOnce()
                guard let tokenError, tokenError.shouldRetry else { return dashboard }
                partial = dashboard
                throw tokenError
            } catch let error as CodexUsageClientError {
                Self.logger.error("Codex attempt \(attempt + 1): \(error.diagnosticCode, privacy: .public)")
                if attempt == 0 && error.shouldRetry {
                    Thread.sleep(forTimeInterval: 0.25)
                    continue
                }
                let finalError = attempt == 1
                    ? CodexUsageClientError.retryFailed(error.localizedDescription) : error
                // A failed optional Token request must never hide valid quota data.
                if let partial {
                    return UsageDashboardSnapshot(quota: partial.quota, tokenUsage: nil,
                                                  tokenUsageError: finalError.localizedDescription)
                }
                throw finalError
            }
        }
        throw CodexUsageClientError.serverExited
    }

    private func fetchOnce() throws -> (UsageDashboardSnapshot, CodexUsageClientError?) {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() } catch { throw CodexUsageClientError.launchFailed }
        // Parent must not hold child pipe ends open, otherwise EOF cannot be observed.
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        defer {
            try? input.fileHandleForWriting.close()
            stopCodexProcess(process)
            try? output.fileHandleForReading.close()
            try? errors.fileHandleForReading.close()
        }
        var reader = JSONLineReader(handle: output.fileHandleForReading,
                                    errors: errors.fileHandleForReading,
                                    deadline: ProcessInfo.processInfo.systemUptime + timeout)
        try send([
            "method": "initialize", "id": 0,
            "params": ["clientInfo": ["name": "codex_usage_alert", "title": "Codex Usage Alert",
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"]],
        ], to: input.fileHandleForWriting)
        _ = try waitForResponse(id: 0, reader: &reader)
        try send(["method": "initialized", "params": [:]], to: input.fileHandleForWriting)
        try send(["method": "account/rateLimits/read", "id": 1], to: input.fileHandleForWriting)
        let response = try waitForResponse(id: 1, reader: &reader)
        let quota = try Self.parseSnapshot(response)
        do {
            try send(["method": "account/usage/read", "id": 2], to: input.fileHandleForWriting)
            let usageResponse = try waitForResponse(id: 2, reader: &reader)
            return (UsageDashboardSnapshot(quota: quota, tokenUsage: try Self.parseTokenUsage(usageResponse)), nil)
        } catch {
            return (UsageDashboardSnapshot(quota: quota, tokenUsage: nil,
                                           tokenUsageError: error.localizedDescription), error as? CodexUsageClientError)
        }
    }

    private func waitForResponse(id: Int, reader: inout JSONLineReader) throws -> [String: Any] {
        while let message = try reader.nextObject() {
            if message["method"] as? String == "account/chatgptAuthTokens/refresh" {
                throw CodexUsageClientError.authenticationRequired
            }
            // Notifications and responses to other requests must not satisfy/fail this RPC.
            guard message["method"] == nil, (message["id"] as? NSNumber)?.intValue == id else { continue }
            if let error = message["error"] as? [String: Any] {
                let code = (error["code"] as? NSNumber)?.intValue
                let text = error["message"] as? String ?? "未知服务错误"
                if code == -32601 {
                    throw CodexUsageClientError.invalidResponse("当前 Codex CLI 不支持此用量接口，请更新 Codex。")
                }
                throw CodexUsageClientError.fromServerMessage(text, code: code)
            }
            return message
        }
        let diagnostic = CodexUsageClientError.fromServerMessage(reader.stderrText)
        if case .authenticationRequired = diagnostic { throw diagnostic }
        if case .timedOut = diagnostic { throw diagnostic }
        throw CodexUsageClientError.serverExited
    }

    private func send(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        do { try handle.write(contentsOf: data) }
        catch { throw CodexUsageClientError.serverExited }
    }

    private static func parseSnapshot(_ response: [String: Any]) throws -> UsageSnapshot {
        guard let result = response["result"] as? [String: Any] else {
            throw CodexUsageClientError.invalidResponse("缺少 result")
        }

        let bucket: [String: Any]?
        if let all = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = all["codex"] as? [String: Any] {
            bucket = codex
        } else {
            bucket = result["rateLimits"] as? [String: Any]
        }

        guard let bucket,
              let primary = bucket["primary"] as? [String: Any],
              let used = (primary["usedPercent"] as? NSNumber)?.doubleValue,
              let window = (primary["windowDurationMins"] as? NSNumber)?.doubleValue,
              let reset = (primary["resetsAt"] as? NSNumber)?.doubleValue else {
            throw CodexUsageClientError.invalidResponse("缺少 Codex 主额度窗口")
        }

        return UsageSnapshot(
            usedPercent: used,
            windowDurationMins: window,
            resetsAt: Date(timeIntervalSince1970: reset),
            planType: bucket["planType"] as? String
        )
    }

    static func parseTokenUsage(_ response: [String: Any]) throws -> AccountTokenUsage {
        guard let result = response["result"] as? [String: Any] else {
            throw CodexUsageClientError.invalidResponse("Token 用量缺少 result")
        }

        let summary = result["summary"] as? [String: Any] ?? [:]
        let rawBuckets = result["dailyUsageBuckets"] as? [[String: Any]] ?? []
        let buckets = rawBuckets.compactMap { bucket -> DailyTokenUsage? in
            guard let startDate = bucket["startDate"] as? String,
                  let tokens = (bucket["tokens"] as? NSNumber)?.int64Value else {
                return nil
            }
            return DailyTokenUsage(startDate: startDate, tokens: tokens)
        }

        return AccountTokenUsage(
            summary: TokenUsageSummary(
                lifetimeTokens: (summary["lifetimeTokens"] as? NSNumber)?.int64Value,
                peakDailyTokens: (summary["peakDailyTokens"] as? NSNumber)?.int64Value,
                longestRunningTurnSec: (summary["longestRunningTurnSec"] as? NSNumber)?.int64Value,
                currentStreakDays: (summary["currentStreakDays"] as? NSNumber)?.intValue,
                longestStreakDays: (summary["longestStreakDays"] as? NSNumber)?.intValue
            ),
            dailyUsageBuckets: buckets
        )
    }
}

private struct JSONLineReader {
    let handle: FileHandle
    let errors: FileHandle
    let deadline: TimeInterval
    private var buffer = Data()
    private var stderr = Data()
    private var stderrOpen = true
    private var stdoutOpen = true
    var stderrText: String { String(decoding: stderr, as: UTF8.self) }

    init(handle: FileHandle, errors: FileHandle, deadline: TimeInterval) {
        self.handle = handle
        self.errors = errors
        self.deadline = deadline
    }

    mutating func nextObject() throws -> [String: Any]? {
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw CodexUsageClientError.timedOut }
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard !line.isEmpty else { continue }
                guard let dictionary = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
                    throw CodexUsageClientError.invalidResponse("App Server 输出不是有效 JSON 对象")
                }
                return dictionary
            }
            guard stdoutOpen else {
                if !buffer.isEmpty { throw CodexUsageClientError.invalidResponse("App Server 返回了不完整的数据") }
                return nil
            }
            var descriptors = [
                pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0),
                pollfd(fd: stderrOpen ? errors.fileDescriptor : -1, events: Int16(POLLIN), revents: 0),
            ]
            let result = poll(&descriptors, 2, Int32(min(remaining * 1000 + 1, 100)))
            if result < 0 {
                if errno == EINTR { continue }
                throw CodexUsageClientError.serverExited
            }
            if result == 0 { continue }
            // Drain both pipes. Unread stderr can fill and deadlock an otherwise healthy server.
            for index in [1, 0] where descriptors[index].revents != 0 {
                var bytes = [UInt8](repeating: 0, count: 8192)
                let count = read(descriptors[index].fd, &bytes, bytes.count)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw CodexUsageClientError.serverExited
                }
                if count == 0 {
                    if index == 0 { stdoutOpen = false } else { stderrOpen = false }
                } else if index == 0 {
                    buffer.append(contentsOf: bytes.prefix(count))
                    guard buffer.count <= 4 * 1024 * 1024 else {
                        throw CodexUsageClientError.invalidResponse("App Server 响应过大")
                    }
                } else {
                    stderr.append(contentsOf: bytes.prefix(count))
                    if stderr.count > 16 * 1024 { stderr.removeFirst(stderr.count - 16 * 1024) }
                }
            }
        }
    }
}
