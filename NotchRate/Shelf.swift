import Foundation
import Observation

/// Files dropped on the notch. Plain paths in UserDefaults; the app is not sandboxed.
@MainActor
@Observable
final class Shelf {
    private(set) var items: [URL] = []  // newest first
    private let defaults: UserDefaults
    static let max = 20

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        items = (defaults.stringArray(forKey: Pref.shelf) ?? []).map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        for url in urls.reversed() {
            items.removeAll { $0 == url }
            items.insert(url, at: 0)
        }
        items = Array(items.prefix(Self.max))  // ponytail: fixed cap, oldest dropped
        save()
    }

    func remove(_ url: URL) { items.removeAll { $0 == url }; save() }
    func clear() { items = []; save() }

    private func save() { defaults.set(items.map(\.path), forKey: Pref.shelf) }
}
