import Foundation
import Darwin

/// Resolve independently of the sparse PATH inherited by Finder/login-item launches.
enum CodexExecutableResolver {
    static func resolve(
        customPath: String? = nil,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        applicationsDirectory: String = "/Applications",
        isExecutable: (String) -> Bool = isExecutableFile,
        loginShellPath: () -> String? = readLoginShellPath
    ) -> URL? {
        func executable(_ path: String) -> URL? {
            guard path.hasPrefix("/"), isExecutable(path) else { return nil }
            return URL(fileURLWithPath: path)
        }
        let custom = customPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty {
            let expanded = custom.hasPrefix("~/") ? homeDirectory + String(custom.dropFirst()) : custom
            // An explicit override must not silently select a different installation.
            return executable(expanded)
        }
        let candidates = [
            homeDirectory + "/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            applicationsDirectory + "/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            applicationsDirectory + "/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            applicationsDirectory + "/ChatGPT.app/Contents/Resources/codex",
            applicationsDirectory + "/Codex.app/Contents/Resources/codex",
        ]
        for path in candidates {
            if let url = executable(path) { return url }
        }
        if let path = loginShellPath() {
            for directory in path.split(separator: ":") {
                if let url = executable(String(directory) + "/codex") { return url }
            }
        }
        return nil
    }

    private static func isExecutableFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }

    static func readLoginShellPath() -> String? {
        let process = Process()
        let output = Pipe()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "printf '\\n__CODEX_USAGE_PATH__%s\\n' \"$PATH\""]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        try? output.fileHandleForWriting.close()
        defer {
            stopCodexProcess(process)
            try? output.fileHandleForReading.close()
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        var data = Data()
        while ProcessInfo.processInfo.systemUptime < deadline {
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor,
                                    events: Int16(POLLIN), revents: 0)
            let result = poll(&descriptor, 1, 50)
            if result < 0 { if errno == EINTR { continue }; return nil }
            if result == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = read(descriptor.fd, &bytes, bytes.count)
            if count <= 0 { break }
            data.append(contentsOf: bytes.prefix(count))
            guard data.count <= 256 * 1024 else { return nil }
            let text = String(decoding: data, as: UTF8.self)
            if let marker = text.range(of: "\n__CODEX_USAGE_PATH__"),
               let end = text[marker.upperBound...].firstIndex(of: "\n") {
                return String(text[marker.upperBound..<end])
            }
        }
        return nil
    }
}

/// Reap only the child we launched, including servers that ignore SIGTERM.
func stopCodexProcess(_ process: Process) {
    if process.isRunning {
        process.terminate()
        let deadline = ProcessInfo.processInfo.systemUptime + 0.2
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(10_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
    process.waitUntilExit()
}
