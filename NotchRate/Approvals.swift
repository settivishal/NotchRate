import Foundation
import Observation

/// Claude Code's PermissionRequest hook (adapter `permission` mode) drops the raw request in
/// ~/.notch-usage/pending/<id>.raw and waits for answer/<id>. `plan-*.raw` files only notify.
@MainActor
@Observable
final class Approvals {
    struct Request: Equatable, Identifiable, Sendable {
        let id: String        // file stem; also the answer file name
        let tool: String
        let detail: String    // command / path / description, whatever the tool has
        let expires: Date     // hook gives up and the terminal prompt takes over
        let isPlan: Bool
        let plan: String?     // ExitPlanMode markdown
        let input: Data       // raw tool_input JSON; ExitPlanMode must get it echoed back as updatedInput
    }

    // Keep in sync with NOTCH_APPROVAL_WAIT / NOTCH_PLAN_WAIT defaults in the adapter.
    nonisolated static let wait: TimeInterval = 15
    nonisolated static let planWait: TimeInterval = 90

    private(set) var pending: [Request] = []
    var onPlanReady: (() -> Void)?
    var onChange: (() -> Void)?

    let directory: URL
    private var source: DispatchSourceFileSystemObject?
    private var reloadTask: Task<Void, Never>?

    var current: Request? { pending.first }

    init(directory: URL) {
        self.directory = directory.appending(path: "pending")
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        reload()
        let fd = open(self.directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            self?.reloadTask?.cancel()
            self?.reloadTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                self?.reload()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    /// `decision`: "allow", "allow <mode>" (session setMode, e.g. acceptEdits) or "deny".
    /// Plans need `updatedInput` alongside allow (Claude Code requires it for ExitPlanMode), so the
    /// full decision JSON is written and the adapter passes it through.
    func answer(_ r: Request, _ decision: String) {
        let dir = directory.deletingLastPathComponent().appending(path: "answer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = r.isPlan && decision.hasPrefix("allow") ? Self.planDecision(input: r.input, mode: decision.split(separator: " ").dropFirst().first.map(String.init)) : decision
        try? out.write(to: dir.appending(path: r.id), atomically: true, encoding: .utf8)
        pending.removeAll { $0.id == r.id }  // hook deletes the file; do not wait for the watcher
        onChange?()
    }

    private func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let new = files.filter { $0.pathExtension == "raw" }.compactMap(Self.parse).sorted { $0.expires < $1.expires }
        if new.contains(where: \.isPlan) && !pending.contains(where: \.isPlan) { onPlanReady?() }
        guard new != pending else { return }
        pending = new
        onChange?()
    }

    nonisolated static func planDecision(input: Data, mode: String?) -> String {
        var d: [String: Any] = ["behavior": "allow", "updatedInput": (try? JSONSerialization.jsonObject(with: input)) ?? [:]]
        if let mode { d["updatedPermissions"] = [["type": "setMode", "mode": mode, "destination": "session"]] }
        let obj = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": d]]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: obj)) ?? Data(), as: UTF8.self)
    }

    nonisolated static func parse(_ url: URL) -> Request? {
        guard let data = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let input = json["tool_input"] as? [String: Any] ?? [:]
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        let id = url.deletingPathExtension().lastPathComponent, isPlan = id.hasPrefix("plan-")
        return Request(id: id, tool: json["tool_name"] as? String ?? "?",
                       detail: (["command", "file_path", "description", "url", "prompt"].lazy.compactMap { input[$0] as? String }.first ?? "").prefix(300).description,
                       expires: mtime.addingTimeInterval(isPlan ? planWait : wait), isPlan: isPlan, plan: input["plan"] as? String,
                       input: (try? JSONSerialization.data(withJSONObject: input)) ?? Data("{}".utf8))
    }
}
