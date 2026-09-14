import Foundation
import Observation

/// Watches ~/.notch-usage for adapter writes. No polling: a DispatchSource on the
/// directory fd fires on the adapter's atomic rename.
@MainActor
@Observable
final class UsageStore {
    private(set) var snapshots: [UsageSnapshot] = []
    var onUpdate: (([UsageSnapshot], [UsageSnapshot]) -> Void)?  // (old, new)

    let directory: URL
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var reloadTask: Task<Void, Never>?

    /// Snapshot with highest usage; what the collapsed badge shows.
    var primary: UsageSnapshot? { snapshots.max { $0.peakPct < $1.peakPct } }

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".notch-usage")) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
        watch()
    }

    private func watch() {
        fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in self?.scheduleReload() }
        src.setCancelHandler { [fd] in close(fd) }
        src.resume()
        source = src
    }

    /// Adapter does tmp+rename, which can fire twice; coalesce within 50ms.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            reload()
        }
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let new = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> UsageSnapshot? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? UsageSnapshot.decoder.decode(UsageSnapshot.self, from: data)
            }
            .sorted { $0.tool < $1.tool }
        guard new != snapshots else { return }
        let old = snapshots
        snapshots = new
        onUpdate?(old, new)
    }
}
