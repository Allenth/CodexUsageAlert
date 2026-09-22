import AppKit
import Foundation
import UsageCore

struct CodexExecutableGrant: Sendable {
    let selectedURL: URL
    let executableURL: URL

    var displayName: String {
        selectedURL.lastPathComponent
    }
}

struct CodexHomeGrant: Sendable {
    let selectedURL: URL

    var displayName: String {
        selectedURL.lastPathComponent
    }
}

enum CodexAccessStoreError: LocalizedError {
    case unsupportedSelection
    case missingCodexAuthentication

    var errorDescription: String? {
        switch self {
        case .unsupportedSelection:
            return "所选项目中没有找到可执行的 Codex 程序。"
        case .missingCodexAuthentication:
            return "所选文件夹中没有找到 Codex 登录资料（auth.json）。"
        }
    }
}

@MainActor
final class CodexAccessStore {
    private let defaults: UserDefaults
    private let bookmarkKey = "codexSecurityScopedBookmark"
    private let codexHomeBookmarkKey = "codexHomeSecurityScopedBookmark"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadGrant() -> CodexExecutableGrant? {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else { return nil }

        do {
            var isStale = false
            let selectedURL = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let didStartSecurityScope = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if didStartSecurityScope {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
            }
            guard let executableURL = CodexAppServerClient.resolveExecutable(
                fromUserSelection: selectedURL
            ) else {
                defaults.removeObject(forKey: bookmarkKey)
                return nil
            }

            if isStale {
                try saveBookmark(for: selectedURL)
            }
            return CodexExecutableGrant(
                selectedURL: selectedURL,
                executableURL: executableURL
            )
        } catch {
            defaults.removeObject(forKey: bookmarkKey)
            return nil
        }
    }

    func chooseGrant() throws -> CodexExecutableGrant? {
        let panel = NSOpenPanel()
        panel.title = L("选择 Codex 或 ChatGPT 应用", "Choose the Codex or ChatGPT app")
        panel.message = L(
            "请选择 Codex.app、ChatGPT.app，或 codex 可执行文件。",
            "Choose Codex.app, ChatGPT.app, or the codex executable."
        )
        panel.prompt = L("授权读取", "Allow Access")
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return nil }
        let didStartSecurityScope = selectedURL.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                selectedURL.stopAccessingSecurityScopedResource()
            }
        }
        guard let executableURL = CodexAppServerClient.resolveExecutable(
            fromUserSelection: selectedURL
        ) else {
            throw CodexAccessStoreError.unsupportedSelection
        }

        try saveBookmark(for: selectedURL)
        return CodexExecutableGrant(
            selectedURL: selectedURL,
            executableURL: executableURL
        )
    }

    func loadCodexHomeGrant() -> CodexHomeGrant? {
        guard let bookmark = defaults.data(forKey: codexHomeBookmarkKey) else { return nil }

        do {
            var isStale = false
            let selectedURL = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let didStartSecurityScope = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if didStartSecurityScope {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
            }
            guard CodexAppServerClient.containsCodexAuthentication(selectedURL) else {
                defaults.removeObject(forKey: codexHomeBookmarkKey)
                return nil
            }

            if isStale {
                try saveBookmark(for: selectedURL, key: codexHomeBookmarkKey)
            }
            return CodexHomeGrant(selectedURL: selectedURL)
        } catch {
            defaults.removeObject(forKey: codexHomeBookmarkKey)
            return nil
        }
    }

    func chooseCodexHomeGrant() throws -> CodexHomeGrant? {
        let panel = NSOpenPanel()
        panel.title = L("选择 Codex 登录资料文件夹", "Choose the Codex sign-in data folder")
        panel.message = L(
            "请选择包含 auth.json 的 .codex 文件夹。可按 ⌘⇧G 输入 ~/.codex。",
            "Choose the .codex folder containing auth.json. Press ⌘⇧G and enter ~/.codex."
        )
        panel.prompt = L("授权读取", "Allow Access")
        panel.directoryURL = URL(fileURLWithPath: "/Users", isDirectory: true)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return nil }
        let didStartSecurityScope = selectedURL.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                selectedURL.stopAccessingSecurityScopedResource()
            }
        }
        guard CodexAppServerClient.containsCodexAuthentication(selectedURL) else {
            throw CodexAccessStoreError.missingCodexAuthentication
        }

        try saveBookmark(for: selectedURL, key: codexHomeBookmarkKey)
        return CodexHomeGrant(selectedURL: selectedURL)
    }

    func clearGrant() {
        defaults.removeObject(forKey: bookmarkKey)
    }

    func clearCodexHomeGrant() {
        defaults.removeObject(forKey: codexHomeBookmarkKey)
    }

    private func saveBookmark(for selectedURL: URL) throws {
        try saveBookmark(for: selectedURL, key: bookmarkKey)
    }

    private func saveBookmark(for selectedURL: URL, key: String) throws {
        let bookmark = try selectedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: key)
    }
}
