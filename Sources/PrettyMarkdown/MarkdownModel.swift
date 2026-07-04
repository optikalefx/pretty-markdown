import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class MarkdownModel: ObservableObject {
    @Published var fileURL: URL?
    @Published var fileName = "Pretty Markdown"
    @Published var markdown = MarkdownModel.sampleMarkdown
    @Published var lastError: String?
    @Published var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceModeDefaultsKey)
        }
    }
    @Published var fontScale: Double {
        didSet {
            let clamped = Self.clampedFontScale(fontScale)
            if clamped != fontScale {
                fontScale = clamped
                return
            }
            UserDefaults.standard.set(fontScale, forKey: Self.fontScaleDefaultsKey)
        }
    }

    private static let appearanceModeDefaultsKey = "appearanceMode"
    private static let fontScaleDefaultsKey = "fontScale"
    private static let defaultFontScale = 1.0
    private static let fontScaleStep = 0.1
    private static let fontScaleRange = 0.7...1.6
    private var lastModified: Date?

    private static let sampleMarkdown: String = {
        guard let url = Bundle.module.url(forResource: "Sample", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "# Pretty Markdown\n\nOpen or drop a `.md` file to get started."
        }
        return text
    }()

    init() {
        let storedAppearance = UserDefaults.standard.string(forKey: Self.appearanceModeDefaultsKey)
        appearanceMode = storedAppearance.flatMap(AppearanceMode.init(rawValue:)) ?? .system

        let stored = UserDefaults.standard.double(forKey: Self.fontScaleDefaultsKey)
        fontScale = stored == 0 ? Self.defaultFontScale : Self.clampedFontScale(stored)
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.markdownDocument, .plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    func open(_ url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            markdown = text
            fileURL = url
            fileName = url.deletingPathExtension().lastPathComponent
            lastModified = modificationDate(for: url)
            lastError = nil
            RecentFiles.shared.add(url)
        } catch {
            lastError = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func reloadCurrentFile() {
        guard let fileURL else { return }
        open(fileURL)
    }

    func reloadIfChanged() {
        guard let fileURL else { return }
        let current = modificationDate(for: fileURL)
        if current != nil, current != lastModified {
            open(fileURL)
        }
    }

    func cycleAppearanceMode() {
        appearanceMode = appearanceMode.next
    }

    func increaseFontSize() {
        adjustFontScale(by: Self.fontScaleStep)
    }

    func decreaseFontSize() {
        adjustFontScale(by: -Self.fontScaleStep)
    }

    func resetFontSize() {
        fontScale = Self.defaultFontScale
    }

    private func adjustFontScale(by delta: Double) {
        fontScale = Self.clampedFontScale(((fontScale + delta) * 10).rounded() / 10)
    }

    private static func clampedFontScale(_ scale: Double) -> Double {
        min(max(scale, fontScaleRange.lowerBound), fontScaleRange.upperBound)
    }

    private func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
