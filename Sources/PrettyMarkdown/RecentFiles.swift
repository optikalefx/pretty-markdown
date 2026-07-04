import Foundation

@MainActor
final class RecentFiles: ObservableObject {
    static let shared = RecentFiles()
    private static let key = "recentFilePaths"
    private static let max = 10

    @Published private(set) var urls: [URL] = []

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        urls = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ url: URL) {
        var updated = urls.filter { $0 != url }
        updated.insert(url, at: 0)
        if updated.count > Self.max { updated = Array(updated.prefix(Self.max)) }
        urls = updated
        UserDefaults.standard.set(updated.map(\.path), forKey: Self.key)
    }

    func clear() {
        urls = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
