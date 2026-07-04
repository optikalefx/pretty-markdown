import Foundation

/// Buffers file-open requests that arrive (from Finder / the app delegate)
/// before the UI has installed a handler.
@MainActor
enum OpenFileRouter {
    private static var opener: ((URL) -> Void)?
    private static var pendingURLs: [URL] = []

    static func install(_ handler: @escaping (URL) -> Void) {
        opener = handler
        let urls = pendingURLs
        pendingURLs.removeAll()
        urls.forEach(handler)
    }

    static func open(_ url: URL) {
        if let opener {
            opener(url)
        } else {
            pendingURLs.append(url)
        }
    }
}
