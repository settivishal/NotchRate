import Foundation
import Testing
@testable import NotchRate

@MainActor
@Test func shelfDedupesCapsAndPersists() throws {
    let suite = UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let files = (0..<25).map { dir.appending(path: "f\($0)") }
    for f in files { try Data().write(to: f) }

    let shelf = Shelf(defaults: defaults)
    shelf.add([files[0]])
    shelf.add([files[0], files[1]])
    #expect(shelf.items == [files[0], files[1]])
    shelf.add(files)
    #expect(shelf.items.count == Shelf.max && shelf.items.first == files[0])
    shelf.remove(files[0])
    #expect(!shelf.items.contains(files[0]))

    try FileManager.default.removeItem(at: files[1])
    let reloaded = Shelf(defaults: defaults)
    #expect(reloaded.items.count == shelf.items.count - 1 && !reloaded.items.contains(files[1]))
}
