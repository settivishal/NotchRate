import Foundation

/// Claude Code's statusLine hook runs the bundled adapter, which dumps the raw JSON to
/// `claude-code.raw`. This turns it into the normalized `claude-code.json` and wires the
/// hook into ~/.claude/settings.json so users never touch a terminal.
enum Statusline {
    static let adapter = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".notch-usage/bin/claude-code.sh")
    static let settings = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json")

    /// Converts `claude-code.raw` (if present) into `claude-code.json`, then deletes it.
    static func ingest(directory: URL) {
        let raw = directory.appending(path: "claude-code.raw"), out = directory.appending(path: "claude-code.json")
        guard let data = try? Data(contentsOf: raw) else { return }
        defer { try? FileManager.default.removeItem(at: raw) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let existing = (try? JSONSerialization.jsonObject(with: Data(contentsOf: out)) as? [String: Any]) ?? [:]
        let mtime = (try? raw.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        try? (try? JSONSerialization.data(withJSONObject: merge(json, into: existing, now: mtime)))?.write(to: out, options: .atomic)
    }

    /// Claude Code caches rate_limits and lags the real numbers, so when the API poller
    /// owns the file (source == "api") only cost/context are taken from the statusline.
    static func merge(_ json: [String: Any], into existing: [String: Any], now: Date = .now) -> [String: Any] {
        var out = existing["source"] as? String == "api" ? existing : [:]
        out["tool"] = "claude-code"
        out["last_updated"] = now.timeIntervalSince1970.rounded(.down)
        out["cost_usd"] = (json["cost"] as? [String: Any])?["total_cost_usd"]
        out["context_pct"] = (json["context_window"] as? [String: Any])?["used_percentage"]
        guard out["source"] as? String != "api" else { return out }
        let limits = json["rate_limits"] as? [String: Any]
        for (bucket, key) in [("five_hour", "session"), ("seven_day", "weekly")] {
            let b = limits?[bucket] as? [String: Any]
            out["\(key)_used_pct"] = b?["used_percentage"]
            out["\(key)_resets_at"] = b?["resets_at"]
        }
        return out
    }

    // MARK: install

    static var isInstalled: Bool { statusLineInstalled && hooksInstalled(current) }

    private static var current: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]) ?? [:] }
    private static var statusLineInstalled: Bool { (current["statusLine"] as? [String: Any])?["command"] as? String == adapter.path }

    /// Permission island hooks: `permission` blocks on PermissionRequest, `clear` drops stale requests.
    static let hookEvents: [String: String] = [
        "PermissionRequest": "permission", "PreToolUse": "clear", "PostToolUse": "clear", "Stop": "clear", "UserPromptSubmit": "clear",
    ]

    static func hooksInstalled(_ s: [String: Any]) -> Bool {
        let hooks = s["hooks"] as? [String: Any] ?? [:]
        return hookEvents.allSatisfy { event, mode in
            (hooks[event] as? [[String: Any]] ?? []).contains { entry in
                (entry["hooks"] as? [[String: Any]] ?? []).contains { $0["command"] as? String == "\(adapter.path) \(mode)" }
            }
        }
    }

    /// Adds our hook entries (once) alongside whatever the user already has.
    static func addHooks(to s: [String: Any]) -> [String: Any] {
        var s = s
        var hooks = s["hooks"] as? [String: Any] ?? [:]
        for (event, mode) in hookEvents {
            let command = "\(adapter.path) \(mode)"
            var entries = hooks[event] as? [[String: Any]] ?? []
            guard !entries.contains(where: { ($0["hooks"] as? [[String: Any]] ?? []).contains { $0["command"] as? String == command } }) else { continue }
            var hook: [String: Any] = ["type": "command", "command": command]
            if mode == "permission" { hook["timeout"] = 30 }
            entries.append(["hooks": [hook]])
            hooks[event] = entries
        }
        s["hooks"] = hooks
        return s
    }

    /// Copies the bundled adapter out of the app (so moving the app does not break the hook)
    /// and points statusLine.command at it. Previous settings.json kept as settings.json.bak.
    static func install() throws {
        guard let src = Bundle.main.url(forResource: "claude-code", withExtension: "sh") else { throw CocoaError(.fileNoSuchFile) }
        let fm = FileManager.default
        try fm.createDirectory(at: adapter.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: adapter.path) { try fm.removeItem(at: adapter) }
        try fm.copyItem(at: src, to: adapter)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adapter.path)
        guard !isInstalled else { return }
        var s = (try? JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]) ?? [:]
        var line = s["statusLine"] as? [String: Any] ?? [:]
        line["type"] = "command"
        line["command"] = adapter.path
        s["statusLine"] = line
        s = addHooks(to: s)
        try fm.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bak = settings.appendingPathExtension("bak")
        if fm.fileExists(atPath: settings.path) { try? fm.removeItem(at: bak); try? fm.copyItem(at: settings, to: bak) }
        try JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted, .sortedKeys]).write(to: settings, options: .atomic)
    }

    /// Adapter and hook set may change between releases; refresh the installed copy on launch.
    static func refreshIfInstalled() {
        guard statusLineInstalled, let src = Bundle.main.url(forResource: "claude-code", withExtension: "sh"), let new = try? Data(contentsOf: src),
              new != (try? Data(contentsOf: adapter)) || !hooksInstalled(current) else { return }
        try? install()
    }
}
