import AppKit

/// The «… с Claude» buttons: a new Claude Code session in Meal Planner's folder with the request, or a new chat
/// with the request on the clipboard — a chat request that arrives in a link, claude.ai meets with a warning.
/// Either way Claude reads and writes the data through Meal Planner's MCP server.
enum ClaudeHandoff {
    static let bundleID = "com.anthropic.claudefordesktop"

    enum Target: String, CaseIterable, Identifiable, Sendable {
        /// A Claude Code session in `ClaudeWorkspace`: its instructions, and the data through MCP.
        case code
        /// A new chat; the request waits on the clipboard.
        case chat

        var id: Self {
            self
        }
    }

    /// Where the buttons open Claude, as Settings → Claude has it.
    static let targetKey = "claudeTarget"

    static var target: Target {
        UserDefaults.standard.string(forKey: targetKey).flatMap(Target.init) ?? .code
    }

    static var isDesktopInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// The sidebar section a Claude Code session files itself under. Claude Desktop starts a session from a link
    /// in a temporary folder once the folder is trusted, so the folder cannot group the sessions.
    static let sidebarSection = "Meal Planner"

    /// The request as a Claude Code session gets it, ending with filing itself under `sidebarSection` — at the
    /// end, since Claude Desktop titles the session after its beginning.
    static func forCodeSession(_ request: String) -> String {
        request + "\n\n"
            + "Перед ответом перенеси эту сессию в раздел «\(sidebarSection)» боковой панели Claude: найди его через "
            + "list_sections и вызови move_sessions с session_ids [\"self\"]; если такого раздела нет, пропусти этот шаг."
    }

    /// Opens the request where `target` says; a chat when Claude Desktop is missing or the folder cannot be
    /// prepared. The request goes to the clipboard either way.
    @MainActor
    static func send(_ request: String, target: Target = Self.target, workspace: ClaudeWorkspace?) {
        let desktop = isDesktopInstalled
        let request = target == .code && desktop ? forCodeSession(request) : request
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(request, forType: .string)
        if target == .code, desktop, let workspace {
            do {
                try workspace.prepare()
                if let session = codeSession(request, folder: workspace.folder) {
                    NSWorkspace.shared.open(session)
                    return
                }
            } catch {
                AppModel.log.error("Claude's folder is not ready: \(error, privacy: .public)")
            }
        }
        if let chat = URL(string: desktop ? "claude://claude.ai/new" : "https://claude.ai/new") {
            NSWorkspace.shared.open(chat)
        }
    }

    /// `claude://code/new?folder=…&q=…`: Claude Desktop's link for a new Claude Code session in a folder, with
    /// the request. Everything but unreserved ASCII is percent-encoded: a bare «+» would turn into a space.
    static func codeSession(_ request: String, folder: URL) -> URL? {
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var path = folder.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        guard let path = path.addingPercentEncoding(withAllowedCharacters: unreserved),
            let text = request.addingPercentEncoding(withAllowedCharacters: unreserved)
        else { return nil }
        return URL(string: "claude://code/new?folder=\(path)&q=\(text)")
    }
}
