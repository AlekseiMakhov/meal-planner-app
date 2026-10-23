import Foundation

/// Meal Planner's server in Claude Desktop's config: whether it is there, the snippet to add by hand, and adding
/// or removing it. Everything else in the config stays as it was, and the previous file is kept next to it with
/// the date in its name.
struct ClaudeConnection {
    enum State: Equatable {
        /// The config has our server with this app's command.
        case connected
        /// The config has our server, but it starts another copy of the app.
        case otherCopy(String)
        case missing
        /// The config is not valid JSON; it is left alone.
        case unreadable(String)
    }

    struct ConfigError: Error, CustomStringConvertible {
        let description: String
    }

    /// Debug builds get a name of their own, so both can be connected at once.
    let serverName: String
    /// The server inside this app's bundle; updating the app updates the server.
    let command: String
    let config: URL

    static let defaultConfig = FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Library/Application Support/Claude/claude_desktop_config.json")

    static var current: ClaudeConnection {
        ClaudeConnection(
            serverName: AppModel.isDebugBuild ? "meal-planner-debug" : "meal-planner",
            command: Bundle.main.bundleURL.appending(path: "Contents/Helpers/meal-planner-mcp").path(
                percentEncoded: false),
            config: defaultConfig)
    }

    var entry: [String: Any] {
        ["command": command]
    }

    /// What to add to `mcpServers` by hand, written the way people write the config.
    var snippet: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let quoted = { (text: String) in
            (try? encoder.encode(text)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        }
        return """
            {
              "mcpServers": {
                \(quoted(serverName)): {
                  "command": \(quoted(command))
                }
              }
            }
            """
    }

    /// The same server for Claude Code in the terminal. The path is quoted for the shell: a Debug build lives in
    /// a folder with spaces and «&».
    var cliCommand: String {
        "claude mcp add --scope user \(serverName) -- '\(command.replacingOccurrences(of: "'", with: #"'\''"#))'"
    }

    func state() -> State {
        let object: [String: Any]
        do {
            guard let read = try read() else { return .missing }
            object = read
        } catch {
            return .unreadable(String(describing: error))
        }
        guard let servers = object["mcpServers"] as? [String: Any], let ours = servers[serverName] as? [String: Any]
        else { return .missing }
        let present = ours["command"] as? String ?? ""
        return present == command ? .connected : .otherCopy(present)
    }

    /// Adds our server or points it at this app; returns the backup of the previous config, if there was one.
    @discardableResult
    func install(now: Date = Date()) throws -> URL? {
        var object = try read() ?? [:]
        var servers = object["mcpServers"] as? [String: Any] ?? [:]
        servers[serverName] = entry
        object["mcpServers"] = servers
        return try write(object, now: now)
    }

    /// Removes our server; other servers and settings stay.
    @discardableResult
    func remove(now: Date = Date()) throws -> URL? {
        guard var object = try read(), var servers = object["mcpServers"] as? [String: Any],
            servers[serverName] != nil
        else { return nil }
        servers[serverName] = nil
        object["mcpServers"] = servers
        return try write(object, now: now)
    }

    /// The config as a JSON object, or nil when there is no file yet.
    private func read() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: config.path(percentEncoded: false)) else { return nil }
        let data = try Data(contentsOf: config)
        if data.isEmpty {
            return [:]
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError(description: "в конфиге не JSON-объект")
        }
        return object
    }

    private func write(_ object: [String: Any], now: Date) throws -> URL? {
        let files = FileManager.default
        try files.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        var backup: URL?
        if files.fileExists(atPath: config.path(percentEncoded: false)) {
            let stamp = now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                .replacingOccurrences(of: ":", with: "-")
            let copy = config.deletingLastPathComponent().appending(path: "\(config.lastPathComponent).backup-\(stamp)")
            try? files.removeItem(at: copy)
            try files.copyItem(at: config, to: copy)
            backup = copy
        }
        let data = try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: config, options: .atomic)
        return backup
    }
}
