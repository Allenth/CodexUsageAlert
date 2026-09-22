import Foundation

public enum CodexUsageClientError: LocalizedError {
    case executableNotFound
    case serverExited
    case timedOut
    case invalidResponse(String)
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "未找到 Codex CLI。请先安装并登录 Codex。"
        case .serverExited:
            return "Codex App Server 在返回用量前退出。"
        case .timedOut:
            return "读取 Codex 用量超时。"
        case .invalidResponse(let detail):
            return "Codex 返回了无法识别的数据：\(detail)"
        case .serverError(let detail):
            return "Codex App Server 错误：\(detail)"
        }
    }
}

public struct CodexAppServerClient: Sendable {
    public let executableURL: URL
    public let securityScopedResourceURL: URL?
    public let codexHomeURL: URL?
    public let timeout: TimeInterval

    public init(
        executableURL: URL? = nil,
        securityScopedResourceURL: URL? = nil,
        codexHomeURL: URL? = nil,
        timeout: TimeInterval = 15
    ) throws {
        guard let resolved = executableURL ?? Self.resolveExecutable() else {
            throw CodexUsageClientError.executableNotFound
        }
        self.executableURL = resolved
        self.securityScopedResourceURL = securityScopedResourceURL
        self.codexHomeURL = codexHomeURL
        self.timeout = timeout
    }

    public static func resolveExecutable() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = String(directory) + "/codex"
                if fileManager.isExecutableFile(atPath: candidate) {
                    return URL(fileURLWithPath: candidate)
                }
            }
        }
        return nil
    }

    public static func resolveExecutable(fromUserSelection selectionURL: URL) -> URL? {
        let fileManager = FileManager.default
        let selection = selectionURL.standardizedFileURL
        let candidates: [URL]

        if selection.pathExtension.lowercased() == "app" {
            candidates = [
                selection.appendingPathComponent("Contents/Resources/codex"),
                selection.appendingPathComponent("Contents/MacOS/codex"),
            ]
        } else if selection.hasDirectoryPath {
            candidates = [
                selection.appendingPathComponent("codex"),
                selection.appendingPathComponent("Contents/Resources/codex"),
                selection.appendingPathComponent("Contents/MacOS/codex"),
            ]
        } else {
            candidates = [selection]
        }

        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) })
    }

    public static func containsCodexAuthentication(_ directoryURL: URL) -> Bool {
        FileManager.default.isReadableFile(
            atPath: directoryURL.appendingPathComponent("auth.json").path
        )
    }

    public func fetchSnapshot() throws -> UsageSnapshot {
        try fetchDashboardSnapshot().quota
    }

    public func fetchDashboardSnapshot() throws -> UsageDashboardSnapshot {
        let securityScopedURLs = [securityScopedResourceURL, codexHomeURL].compactMap { $0 }
        let startedSecurityScopes = securityScopedURLs.filter {
            $0.startAccessingSecurityScopedResource()
        }
        defer {
            for url in startedSecurityScopes {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()

        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        if let codexHomeURL {
            var environment = ProcessInfo.processInfo.environment
            environment["CODEX_HOME"] = codexHomeURL.path
            process.environment = environment
        }

        try process.run()
        let timeoutWork = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + timeout,
            execute: timeoutWork
        )

        defer {
            timeoutWork.cancel()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            try? errors.fileHandleForReading.close()
            if process.isRunning { process.terminate() }
        }

        var reader = JSONLineReader(handle: output.fileHandleForReading)
        try send([
            "method": "initialize",
            "id": 0,
            "params": [
                "clientInfo": [
                    "name": "codex_usage_alert",
                    "title": "Codex Usage Alert",
                    "version": "0.1.0",
                ]
            ],
        ], to: input.fileHandleForWriting)

        _ = try waitForResponse(id: 0, reader: &reader, process: process)
        try send(["method": "initialized", "params": [:]], to: input.fileHandleForWriting)
        try send(["method": "account/rateLimits/read", "id": 1], to: input.fileHandleForWriting)

        let response = try waitForResponse(id: 1, reader: &reader, process: process)
        let quota = try Self.parseSnapshot(response)

        do {
            try send(["method": "account/usage/read", "id": 2], to: input.fileHandleForWriting)
            let usageResponse = try waitForResponse(id: 2, reader: &reader, process: process)
            return UsageDashboardSnapshot(
                quota: quota,
                tokenUsage: try Self.parseTokenUsage(usageResponse)
            )
        } catch {
            return UsageDashboardSnapshot(
                quota: quota,
                tokenUsage: nil,
                tokenUsageError: error.localizedDescription
            )
        }
    }

    private func waitForResponse(
        id: Int,
        reader: inout JSONLineReader,
        process: Process
    ) throws -> [String: Any] {
        while process.isRunning {
            guard let message = try reader.nextObject() else { break }
            if let error = message["error"] as? [String: Any] {
                throw CodexUsageClientError.serverError(
                    error["message"] as? String ?? String(describing: error)
                )
            }
            if (message["id"] as? NSNumber)?.intValue == id {
                return message
            }
        }
        if process.terminationReason == .uncaughtSignal {
            throw CodexUsageClientError.timedOut
        }
        throw CodexUsageClientError.serverExited
    }

    private func send(_ object: [String: Any], to handle: FileHandle) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data([0x0A]))
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
    private var buffer = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    mutating func nextObject() throws -> [String: Any]? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard !line.isEmpty else { continue }
                let object = try JSONSerialization.jsonObject(with: Data(line))
                guard let dictionary = object as? [String: Any] else {
                    throw CodexUsageClientError.invalidResponse("JSON 行不是对象")
                }
                return dictionary
            }

            let chunk = handle.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }
}
