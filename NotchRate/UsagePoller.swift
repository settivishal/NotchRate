import Foundation

/// Statusline only fires while Claude Code runs a turn, but Pro/Max limits are shared
/// with claude.ai chat and Cowork. Poll Anthropic's OAuth usage endpoint with Claude
/// Code's own token so the badge stays accurate while the CLI is idle. Merges into the
/// same ~/.notch-usage/claude-code.json, keeping cost/context from the statusline.
@MainActor
final class UsagePoller {
    private static let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"  // Claude Code's public OAuth client
    private let file: URL
    private var task: Task<Void, Never>?

    init(directory: URL) {
        file = directory.appending(path: "claude-code.json")
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(max(30, UserDefaults.standard.double(forKey: Pref.pollSeconds))))
            }
        }
    }

    deinit { task?.cancel() }

    func poll() async {
        guard var creds = Self.readCreds() else { return }
        // Token lives a few hours; Claude Code refreshes it only when run, so refresh here when past expiry.
        if (creds["expiresAt"] as? Double ?? 0) / 1000 < Date.now.timeIntervalSince1970 + 60 {
            guard let fresh = await Self.refresh(creds) else { return }
            creds = fresh
        }
        guard let token = creds["accessToken"] as? String else { return }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
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
        let extra = json["extra_usage"] as? [String: Any]
        out["extra_pct"] = extra?["is_enabled"] as? Bool == true ? extra?["utilization"] as? Double : nil
        try? (try? JSONSerialization.data(withJSONObject: out))?.write(to: file, options: .atomic)
    }

    // MARK: keychain

    /// `security` CLI is already on the item's ACL (Claude Code writes it that way), so no keychain prompt.
    private static func readCreds() -> [String: Any]? {
        let data = security(["find-generic-password", "-s", "Claude Code-credentials", "-w"])
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["claudeAiOauth"] as? [String: Any]
    }

    /// Refresh tokens rotate, so the new pair must go back to the keychain or Claude Code's next login breaks.
    private static func refresh(_ creds: [String: Any]) async -> [String: Any]? {
        guard let rt = creds["refreshToken"] as? String else { return nil }
        var req = URLRequest(url: URL(string: "https://console.anthropic.com/v1/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["grant_type": "refresh_token", "refresh_token": rt, "client_id": clientId])
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else { return nil }
        var updated = creds
        updated["accessToken"] = access
        updated["refreshToken"] = json["refresh_token"] as? String ?? rt
        updated["expiresAt"] = (Date.now.timeIntervalSince1970 + (json["expires_in"] as? Double ?? 3600)) * 1000
        guard let body = try? JSONSerialization.data(withJSONObject: ["claudeAiOauth": updated]),
              let str = String(data: body, encoding: .utf8) else { return nil }
        _ = security(["add-generic-password", "-U", "-s", "Claude Code-credentials", "-a", NSUserName(), "-w", str])
        return updated
    }

    private static func security(_ args: [String]) -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return Data() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
