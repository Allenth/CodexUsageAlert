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

enum CodexAccessStoreError: LocalizedError {
    case unsupportedSelection

    var errorDescription: String? {
        switch self {
        case .unsupportedSelection:
            return "所选项目中没有找到可执行的 Codex 程序。"
        }
    }
}

@MainActor
final class CodexAccessStore {
    private let defaults: UserDefaults
    private let bookmarkKey = "codexSecurityScopedBookmark"

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
        panel.title = "选择 Codex 或 ChatGPT 应用"
        panel.message = "请选择 Codex.app、ChatGPT.app，或 codex 可执行文件。"
        panel.prompt = "授权读取"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return nil }
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

    func clearGrant() {
        defaults.removeObject(forKey: bookmarkKey)
    }

    private func saveBookmark(for selectedURL: URL) throws {
        let bookmark = try selectedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: bookmarkKey)
    }
}
