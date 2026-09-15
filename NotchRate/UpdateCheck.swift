import Foundation

/// Checks GitHub releases once at launch and daily after; menu shows a link when a newer tag exists.
@MainActor
final class UpdateCheck: ObservableObject {
    @Published var latest: (version: String, url: URL)?
    private var task: Task<Void, Never>?

    init() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(86_400))
            }
        }
    }

    deinit { task?.cancel() }

    func check() async {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/settivishal/NotchRate/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, let page = (json["html_url"] as? String).flatMap(URL.init) else { return }
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        latest = Self.isNewer(tag, than: current) ? (tag, page) : nil
    }

    nonisolated static func isNewer(_ tag: String, than current: String) -> Bool {
        let t = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return t.compare(current, options: .numeric) == .orderedDescending
    }
}
