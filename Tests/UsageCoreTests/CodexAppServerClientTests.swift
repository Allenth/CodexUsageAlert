import Darwin
import Foundation
import XCTest
@testable import UsageCore

final class CodexAppServerClientTests: XCTestCase {
    func testExecutableSearchOrderDoesNotDependOnGUIPath() {
        let paths = [
            "/test-user/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        ]
        for index in paths.indices {
            let available = Set(paths[index...])
            let resolved = CodexExecutableResolver.resolve(
                homeDirectory: "/test-user",
                isExecutable: { available.contains($0) },
                loginShellPath: { XCTFail("Known locations must not launch a login shell"); return nil }
            )
            XCTAssertEqual(resolved?.path, paths[index])
        }
    }

    func testCustomPathHasPriorityAndExpandsTilde() {
        let resolved = CodexExecutableResolver.resolve(
            customPath: "  ~/My Tools/codex  ",
            homeDirectory: "/test-user",
            isExecutable: { _ in true },
            loginShellPath: { XCTFail("Custom path must not launch a login shell"); return nil }
        )
        XCTAssertEqual(resolved?.path, "/test-user/My Tools/codex")
    }

    func testInvalidCustomPathDoesNotSilentlyUseAnotherCLI() {
        let resolved = CodexExecutableResolver.resolve(
            customPath: "/missing/codex",
            homeDirectory: "/test-user",
            isExecutable: { $0 != "/missing/codex" },
            loginShellPath: { XCTFail("Invalid override must remain visible"); return nil }
        )
        XCTAssertNil(resolved)
    }

    func testLoginShellPathIsLastFallbackAndKeepsPathOrder() {
        var shellCalls = 0
        let resolved = CodexExecutableResolver.resolve(
            customPath: " \n ",
            homeDirectory: "/test-user",
            isExecutable: { ["/tools/one/codex", "/tools/two/codex"].contains($0) },
            loginShellPath: {
                shellCalls += 1
                return "/tools/one:/tools/two"
            }
        )
        XCTAssertEqual(resolved?.path, "/tools/one/codex")
        XCTAssertEqual(shellCalls, 1)
    }

    func testMissingExecutableReturnsNil() {
        XCTAssertNil(CodexExecutableResolver.resolve(
            homeDirectory: "/test-user",
            isExecutable: { _ in false },
            loginShellPath: { "/usr/bin:/bin" }
        ))
    }

    func testHandshakeReadsQuotaAndTokens() throws {
        let server = try MockServer()
        defer { server.remove() }
        try server.writeScript(body: Self.successConversation)
        let dashboard = try server.client().fetchDashboardSnapshot()
        XCTAssertEqual(dashboard.quota.usedPercent, 21)
        XCTAssertEqual(dashboard.quota.remainingPercent, 79)
        XCTAssertEqual(dashboard.tokenUsage?.summary.lifetimeTokens, 123456)
        XCTAssertNil(dashboard.tokenUsageError)
        XCTAssertEqual(try server.processIDs().count, 1)
        let requests = try String(contentsOf: server.requests, encoding: .utf8)
        let methods = try requests.split(whereSeparator: \.isNewline).map { line in
            (try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["method"] as? String
        }
        for method in ["initialize", "initialized", "account/rateLimits/read", "account/usage/read"] {
            XCTAssertTrue(methods.contains(method), "Missing protocol method: \(method)")
        }
    }

    func testFirstTimeoutRetriesUsingFreshProcess() throws {
        let server = try MockServer()
        defer { server.remove() }
        try server.writeScript(body: """
        if [ "$attempt" -eq 1 ]; then
            while :; do :; done
        fi
        \(Self.successConversation)
        """)
        let dashboard = try server.client(timeout: 0.7).fetchDashboardSnapshot()
        XCTAssertEqual(dashboard.quota.usedPercent, 21)
        let pids = try server.processIDs()
        XCTAssertEqual(pids.count, 2)
        XCTAssertEqual(Set(pids).count, 2)
        assertProcessesStopped(pids)
    }

    func testAuthenticationFailureRetriesOnceAndRecovers() throws {
        let server = try MockServer()
        defer { server.remove() }
        try server.writeScript(body: """
        \(Self.handshake)
        if [ "$attempt" -eq 1 ]; then
            printf '%s\\n' '{"id":1,"error":{"code":401,"message":"Unauthorized: authentication required"}}'
            while IFS= read -r request; do :; done
            exit 0
        fi
        \(Self.quotaAndTokens)
        """)
        let dashboard = try server.client().fetchDashboardSnapshot()
        XCTAssertEqual(dashboard.quota.usedPercent, 21)
        XCTAssertEqual(try server.processIDs().count, 2)
    }

    func testPersistentAuthenticationFailureHasActionableMessage() throws {
        let server = try MockServer()
        defer { server.remove() }
        try server.writeScript(body: """
        \(Self.handshake)
        printf '%s\\n' '{"id":1,"error":{"code":401,"message":"Unauthorized: authentication required"}}'
        while IFS= read -r request; do :; done
        """)
        XCTAssertThrowsError(try server.client().fetchDashboardSnapshot()) { error in
            XCTAssertTrue(error.localizedDescription.contains("登录"))
            XCTAssertTrue(error.localizedDescription.contains("重试"))
        }
        XCTAssertEqual(try server.processIDs().count, 2)
    }

    func testPersistentTimeoutIsBoundedAndReapsBothProcesses() throws {
        let server = try MockServer()
        defer { server.remove() }
        try server.writeScript(body: "trap '' TERM\nwhile :; do :; done")
        let started = Date()
        XCTAssertThrowsError(try server.client(timeout: 0.6).fetchDashboardSnapshot()) { error in
            XCTAssertTrue(error.localizedDescription.contains("超时"))
            XCTAssertTrue(error.localizedDescription.contains("重试"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
        let pids = try server.processIDs()
        XCTAssertEqual(pids.count, 2)
        assertProcessesStopped(pids)
    }

    func testLargeStderrDoesNotBlockQuotaRead() throws {
        let server = try MockServer()
        defer { server.remove() }
        try server.writeScript(body: """
        i=0
        while [ "$i" -lt 4096 ]; do
            printf '%s\\n' 'diagnostic output that should be drained, not retained without a bound' >&2
            i=$((i + 1))
        done
        \(Self.successConversation)
        """)
        XCTAssertEqual(try server.client(timeout: 3).fetchSnapshot().usedPercent, 21)
        XCTAssertEqual(try server.processIDs().count, 1)
    }

    func testUnsupportedTokenEndpointKeepsValidQuota() throws {
        let server = try MockServer()
        defer { server.remove() }
        try server.writeScript(body: """
        \(Self.handshake)
        \(Self.quotaResponse)
        read_request
        printf '%s\\n' '{"id":2,"error":{"code":-32601,"message":"Method not found"}}'
        while IFS= read -r request; do :; done
        """)
        let dashboard = try server.client().fetchDashboardSnapshot()
        XCTAssertEqual(dashboard.quota.usedPercent, 21)
        XCTAssertNil(dashboard.tokenUsage)
        XCTAssertNotNil(dashboard.tokenUsageError)
        XCTAssertEqual(try server.processIDs().count, 1)
    }

    func testUnrelatedErrorResponseDoesNotRejectCurrentRequest() throws {
        let server = try MockServer()
        defer { server.remove() }
        try server.writeScript(body: """
        \(Self.handshake)
        printf '%s\\n' '{"id":99,"error":{"code":-32601,"message":"Unrelated request failed"}}'
        \(Self.quotaAndTokens)
        """)
        XCTAssertEqual(try server.client().fetchSnapshot().usedPercent, 21)
        XCTAssertEqual(try server.processIDs().count, 1)
    }

    func testEarlyExitIsNotReportedAsTimeout() throws {
        let server = try MockServer()
        defer { server.remove() }
        try server.writeScript(body: "read_request\nexit 2")
        XCTAssertThrowsError(try server.client().fetchDashboardSnapshot()) { error in
            XCTAssertTrue(error.localizedDescription.contains("退出"))
            XCTAssertFalse(error.localizedDescription.contains("超时"))
            XCTAssertTrue(error.localizedDescription.contains("重试"))
        }
        XCTAssertEqual(try server.processIDs().count, 2)
    }

    func testClosedStdoutWhileServerStillRunsDoesNotCrash() throws {
        let server = try MockServer()
        defer { server.remove() }
        // Regression for querying Process.terminationReason before the process exits.
        try server.writeScript(body: "read_request\nexec 1>&-\nwhile :; do :; done")
        XCTAssertThrowsError(try server.client().fetchDashboardSnapshot()) { error in
            XCTAssertTrue(error.localizedDescription.contains("退出"))
            XCTAssertFalse(error.localizedDescription.contains("超时"))
        }
        let pids = try server.processIDs()
        XCTAssertEqual(pids.count, 2)
        assertProcessesStopped(pids)
    }

    func testTokenTimeoutPreservesQuotaAfterExactlyOneRetry() throws {
        let server = try MockServer()
        defer { server.remove() }
        try server.writeScript(body: """
        \(Self.handshake)
        \(Self.quotaResponse)
        read_request
        while :; do :; done
        """)
        let dashboard = try server.client(timeout: 0.7).fetchDashboardSnapshot()
        XCTAssertEqual(dashboard.quota.usedPercent, 21)
        XCTAssertNil(dashboard.tokenUsage)
        XCTAssertTrue(dashboard.tokenUsageError?.contains("超时") == true)
        XCTAssertTrue(dashboard.tokenUsageError?.contains("重试") == true)
        let pids = try server.processIDs()
        XCTAssertEqual(pids.count, 2)
        assertProcessesStopped(pids)
    }

    func testMalformedQuotaIsNotRetried() throws {
        let server = try MockServer()
        defer { server.remove() }
        try server.writeScript(body: """
        \(Self.handshake)
        printf '%s\\n' '{"id":1,"result":{}}'
        while IFS= read -r request; do :; done
        """)
        XCTAssertThrowsError(try server.client().fetchDashboardSnapshot()) { error in
            guard case CodexUsageClientError.invalidResponse = error else {
                return XCTFail("Expected invalid response, got \(error)")
            }
        }
        XCTAssertEqual(try server.processIDs().count, 1)
    }

    private func assertProcessesStopped(_ pids: [Int32], file: StaticString = #filePath, line: UInt = #line) {
        for pid in pids {
            XCTAssertEqual(kill(pid, 0), -1, "Mock server \(pid) leaked", file: file, line: line)
            XCTAssertEqual(errno, ESRCH, file: file, line: line)
        }
    }

    private static let handshake = """
    read_request
    case "$request" in *'"initialize"'*) ;; *) exit 21 ;; esac
    printf '%s\\n' '{"id":0,"result":{}}'
    read_request
    case "$request" in *'"initialized"'*) ;; *) exit 22 ;; esac
    read_request
    case "$request" in *'account'*'rateLimits'*) ;; *) exit 23 ;; esac
    """

    private static let quotaResponse = """
    printf '%s\\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":21,"windowDurationMins":10080,"resetsAt":1900000000},"planType":"pro"}}}'
    """

    private static let quotaAndTokens = """
    \(quotaResponse)
    read_request
    case "$request" in *'account'*'usage'*) ;; *) exit 24 ;; esac
    printf '%s\\n' '{"id":2,"result":{"summary":{"lifetimeTokens":123456},"dailyUsageBuckets":[]}}'
    while IFS= read -r request; do :; done
    """

    private static let successConversation = "\(handshake)\n\(quotaAndTokens)"
}

private struct MockServer {
    let directory: URL
    let executable: URL
    let pids: URL
    let requests: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-usage-tests-\(UUID().uuidString)")
        executable = directory.appendingPathComponent("mock-codex")
        pids = directory.appendingPathComponent("pids")
        requests = directory.appendingPathComponent("requests")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func writeScript(body: String) throws {
        // The path is a generated temporary-directory name, passed as a literal shell argument.
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let source = """
        #!/bin/sh
        [ "$1" = app-server ] || exit 20
        printf '%s\\n' "$$" >> \(quote(pids.path))
        attempt=$(/usr/bin/wc -l < \(quote(pids.path)))
        read_request() {
            IFS= read -r request || exit 25
            printf '%s\\n' "$request" >> \(quote(requests.path))
        }
        \(body)
        """
        try source.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func client(timeout: TimeInterval = 2) throws -> CodexAppServerClient {
        try CodexAppServerClient(executableURL: executable, timeout: timeout)
    }

    func processIDs() throws -> [Int32] {
        try String(contentsOf: pids, encoding: .utf8).split(whereSeparator: \.isNewline).compactMap { Int32($0) }
    }

    func remove() {
        // Ensure a failed assertion cannot leave a deliberately unresponsive fixture running.
        if let processIDs = try? processIDs() {
            for pid in processIDs where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
        try? FileManager.default.removeItem(at: directory)
    }
}
