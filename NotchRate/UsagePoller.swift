import Foundation

/// Statusline only fires while Claude Code runs a turn, but Pro/Max limits are shared
/// with claude.ai chat and Cowork. Poll Anthropic's OAuth usage endpoint with Claude
/// Code's own token so the badge stays accurate while the CLI is idle. Merges into the
/// same ~/.notch-usage/claude-code.json, keeping cost/context from the statusline.
@MainActor
final class UsagePoller {
    private let file: URL
    private var task: Task<Void, Never>?

    init(directory: URL, interval: Duration = .seconds(60)) {
        file = directory.appending(path: "claude-code.json")
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: interval)
            }
        }
    }

    deinit { task?.cancel() }

    private func poll() async {
        guard let token = Self.keychainToken() else { return }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        // 401 = token expired; Claude Code refreshes it on its next run, so just wait.
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var out = (try? JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]) ?? [:]
        out["tool"] = "claude-code"
        out["last_updated"] = Date.now.timeIntervalSince1970.rounded(.down)
        for (bucket, key) in [("five_hour", "session"), ("seven_day", "weekly")] {
            let b = json[bucket] as? [String: Any]
            out["\(key)_used_pct"] = b?["utilization"] as? Double
            out["\(key)_resets_at"] = (b?["resets_at"] as? String).flatMap { Self.iso.date(from: $0)?.timeIntervalSince1970 }
        }
        try? (try? JSONSerialization.data(withJSONObject: out))?.write(to: file, options: .atomic)
    }

    /// `security` CLI is already on the item's ACL (Claude Code writes it that way), so no keychain prompt.
    private static func keychainToken() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let creds = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (creds?["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
