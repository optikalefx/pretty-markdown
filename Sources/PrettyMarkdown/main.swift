import SwiftUI
import WebKit
import UniformTypeIdentifiers

extension UTType {
    static let markdownDocument = UTType(filenameExtension: "md") ?? .plainText
}

@main
struct PrettyMarkdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MarkdownModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 540)
                .onAppear {
                    OpenFileRouter.install { url in
                        model.open(url)
                    }
                }
                .onOpenURL { url in
                    OpenFileRouter.open(url)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    model.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                OpenRecentMenu(model: model)
            }

            CommandGroup(after: .toolbar) {
                Button("Increase Font Size") {
                    model.increaseFontSize()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Decrease Font Size") {
                    model.decreaseFontSize()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Font Size") {
                    model.resetFontSize()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        OpenFileRouter.open(URL(fileURLWithPath: filename))
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        filenames.forEach { OpenFileRouter.open(URL(fileURLWithPath: $0)) }
        sender.reply(toOpenOrPrint: .success)
    }
}

struct OpenRecentMenu: View {
    let model: MarkdownModel
    @ObservedObject private var recents = RecentFiles.shared

    var body: some View {
        Menu("Open Recent") {
            if recents.urls.isEmpty {
                Text("No Recent Documents")
            } else {
                ForEach(recents.urls, id: \.path) { url in
                    Button(url.lastPathComponent) {
                        model.open(url)
                    }
                }
                Divider()
                Button("Clear Menu") {
                    recents.clear()
                }
            }
        }
    }
}

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

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var next: AppearanceMode {
        switch self {
        case .system: return .light
        case .light:  return .dark
        case .dark:   return .system
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

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

@MainActor
final class MarkdownModel: ObservableObject {
    @Published var fileURL: URL?
    @Published var fileName = "Pretty Markdown"
    @Published var markdown = sampleMarkdown
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

struct ContentView: View {
    @EnvironmentObject private var model: MarkdownModel
    @State private var dropIsTargeted = false

    private let refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack {
                MarkdownWebView(
                    markdown: model.markdown,
                    title: model.fileName,
                    appearanceMode: model.appearanceMode,
                    fontScale: model.fontScale
                )
                    .ignoresSafeArea(.container, edges: .bottom)

                if dropIsTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }
        }
        .onReceive(refreshTimer) { _ in
            model.reloadIfChanged()
        }
        .onDrop(of: [.fileURL], isTargeted: $dropIsTargeted) { providers in
            loadDroppedFile(from: providers)
        }
        .alert("Markdown Viewer", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                model.presentOpenPanel()
            } label: {
                Label("Open", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)

            Button {
                model.cycleAppearanceMode()
            } label: {
                Label(model.appearanceMode.label, systemImage: model.appearanceMode.icon)
            }
            .help("Toggle appearance (\(model.appearanceMode.label))")

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(model.fileName)
                    .font(.headline)
                    .lineLimit(1)
                if let fileURL = model.fileURL {
                    Text(fileURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Open or drop a .md file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 420, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func loadDroppedFile(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = item as? URL
            }

            if let url {
                Task { @MainActor in
                    model.open(url)
                }
            }
        }
        return true
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let title: String
    let appearanceMode: AppearanceMode
    let fontScale: Double

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = MarkdownHTMLRenderer.render(
            markdown: markdown,
            title: title,
            appearanceMode: appearanceMode,
            fontScale: fontScale
        )
        guard html != context.coordinator.lastHTML else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator {
        weak var webView: WKWebView?
        var lastHTML = ""
    }
}

enum MarkdownHTMLRenderer {
    private struct Heading {
        let level: Int
        let title: String
        let id: String
    }

    private struct RenderedContent {
        let body: String
        let headings: [Heading]
    }

    static func render(
        markdown: String,
        title: String,
        appearanceMode: AppearanceMode = .system,
        fontScale: Double = 1.0
    ) -> String {
        let rendered = renderedContent(from: markdown)
        let layoutClass = rendered.headings.isEmpty ? "reading-layout no-toc" : "reading-layout"
        let forcedCSS: String
        switch appearanceMode {
        case .system: forcedCSS = ""
        case .light:  forcedCSS = "\n  <style>\(lightVarsCSS)</style>"
        case .dark:   forcedCSS = "\n  <style>\(darkVarsCSS)</style>"
        }
        let fontScaleCSS = "\n  <style>:root { --font-scale: \(cssNumber(fontScale)); }</style>"
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapeHTML(title))</title>
          <link rel="preconnect" href="https://fonts.googleapis.com">
          <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
          <link href="https://fonts.googleapis.com/css2?family=Merriweather+Sans:ital,wght@0,300..800;1,300..800&display=swap" rel="stylesheet">
          <style>\(themeCSS)</style>\(forcedCSS)\(fontScaleCSS)
        </head>
        <body>
          <div class="\(layoutClass)">
            \(tocHTML(from: rendered.headings))
            <main class="document">
              \(rendered.body)
            </main>
          </div>
          <script>\(scrollSpyScript)</script>
          <script>\(highlightScript)</script>
        </body>
        </html>
        """
    }

    private static func renderedContent(from markdown: String) -> RenderedContent {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var html: [String] = []
        var headings: [Heading] = []
        var usedSlugs: [String: Int] = [:]
        var paragraph: [String] = []
        var listItems: [String] = []
        var orderedItems: [String] = []
        var quoteLines: [String] = []
        var codeLines: [String] = []
        var inCodeBlock = false
        var codeLanguage = ""
        var tableRows: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            html.append("<p>\(inlineHTML(paragraph.joined(separator: " ")))</p>")
            paragraph.removeAll()
        }

        func flushList() {
            guard !listItems.isEmpty else { return }
            html.append("<ul>\(listItems.joined())</ul>")
            listItems.removeAll()
        }

        func flushOrderedList() {
            guard !orderedItems.isEmpty else { return }
            html.append("<ol>\(orderedItems.joined())</ol>")
            orderedItems.removeAll()
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            html.append("<blockquote>\(quoteLines.map { "<p>\(inlineHTML($0))</p>" }.joined())</blockquote>")
            quoteLines.removeAll()
        }

        func parseTableCells(_ row: String) -> [String] {
            var parts = row.components(separatedBy: "|")
            if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeFirst() }
            if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeLast() }
            return parts.map { $0.trimmingCharacters(in: .whitespaces) }
        }

        func isTableSeparator(_ row: String) -> Bool {
            let cells = parseTableCells(row)
            guard !cells.isEmpty else { return false }
            return cells.allSatisfy { cell in
                !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
            }
        }

        func flushTable() {
            guard !tableRows.isEmpty else { return }
            defer { tableRows.removeAll() }
            guard tableRows.count >= 2, isTableSeparator(tableRows[1]) else {
                tableRows.forEach { paragraph.append($0) }
                flushParagraph()
                return
            }
            let headers = parseTableCells(tableRows[0])
            let dataRows = tableRows.dropFirst(2)
            var t = "<table>\n<thead><tr>"
            t += headers.map { "<th>\(inlineHTML($0))</th>" }.joined()
            t += "</tr></thead>\n<tbody>"
            for row in dataRows {
                let cells = parseTableCells(row)
                t += "<tr>"
                t += cells.map { "<td>\(inlineHTML($0))</td>" }.joined()
                t += "</tr>\n"
            }
            t += "</tbody></table>"
            html.append(t)
        }

        func flushFlow() {
            flushParagraph()
            flushList()
            flushOrderedList()
            flushQuote()
            flushTable()
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inCodeBlock {
                    let cls = codeLanguage.isEmpty ? "" : " class=\"language-\(codeLanguage)\""
                    html.append("<pre><code\(cls)>\(escapeHTML(codeLines.joined(separator: "\n")))</code></pre>")
                    codeLines.removeAll()
                    codeLanguage = ""
                    inCodeBlock = false
                } else {
                    flushFlow()
                    codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(rawLine)
                continue
            }

            if line.isEmpty {
                flushFlow()
                continue
            }

            if line == "---" || line == "***" {
                flushFlow()
                html.append("<hr>")
                continue
            }

            if line.hasPrefix("#") {
                let count = line.prefix { $0 == "#" }.count
                if count <= 6, line.dropFirst(count).first == " " {
                    flushFlow()
                    let text = String(line.dropFirst(count + 1))
                    let title = plainText(from: text)
                    let id = uniqueSlug(for: title, usedSlugs: &usedSlugs)
                    headings.append(Heading(level: count, title: title, id: id))
                    html.append("<h\(count) id=\"\(id)\">\(inlineHTML(text))</h\(count)>")
                    continue
                }
            }

            if line.hasPrefix(">") {
                flushParagraph()
                flushList()
                flushOrderedList()
                quoteLines.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                flushOrderedList()
                flushQuote()
                listItems.append(listItemHTML(from: String(line.dropFirst(2))))
                continue
            }

            if let match = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                flushParagraph()
                flushList()
                flushQuote()
                orderedItems.append("<li>\(inlineHTML(String(line[match.upperBound...])))</li>")
                continue
            }

            if line.hasPrefix("|") {
                flushParagraph()
                flushList()
                flushOrderedList()
                flushQuote()
                tableRows.append(line)
                continue
            }

            flushList()
            flushOrderedList()
            flushQuote()
            flushTable()
            paragraph.append(line)
        }

        if inCodeBlock {
            html.append("<pre><code>\(escapeHTML(codeLines.joined(separator: "\n")))</code></pre>")
        }
        flushFlow()
        return RenderedContent(body: html.joined(separator: "\n"), headings: headings)
    }

    private static func tocHTML(from headings: [Heading]) -> String {
        guard !headings.isEmpty else { return "" }
        let links = headings.map { heading in
            """
            <a class="toc-link level-\(heading.level)" href="#\(heading.id)" data-heading-id="\(heading.id)">\(escapeHTML(heading.title))</a>
            """
        }.joined(separator: "\n")

        return """
        <nav class="toc" aria-label="Table of contents">
          <div class="toc-title">Contents</div>
          <div class="toc-links">
            \(links)
          </div>
        </nav>
        """
    }

    private static func inlineHTML(_ text: String) -> String {
        var result = escapeHTML(text)
        result = replace(pattern: #"`([^`]+)`"#, in: result, with: "<code>$1</code>")
        result = replace(pattern: #"\*\*([^*]+)\*\*"#, in: result, with: "<strong>$1</strong>")
        result = replace(pattern: #"(?<!\w)__([^_]+)__(?!\w)"#, in: result, with: "<strong>$1</strong>")
        result = replace(pattern: #"\*([^*]+)\*"#, in: result, with: "<em>$1</em>")
        result = replace(pattern: #"(?<!\w)_([^_\n]+)_(?!\w)"#, in: result, with: "<em>$1</em>")
        result = replace(pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#, in: result, with: "<a href=\"$2\">$1</a>")
        return result
    }

    private static func listItemHTML(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("[ ] ") {
            let body = String(trimmed.dropFirst(4))
            return """
            <li class="task-list-item"><input class="task-list-checkbox" type="checkbox" disabled><span class="task-list-label">\(inlineHTML(body))</span></li>
            """
        }

        if trimmed.range(of: #"^\[[xX]\]\s+"#, options: .regularExpression) != nil {
            let body = String(trimmed.dropFirst(4))
            return """
            <li class="task-list-item checked"><input class="task-list-checkbox" type="checkbox" checked disabled><span class="task-list-label">\(inlineHTML(body))</span></li>
            """
        }

        return "<li>\(inlineHTML(text))</li>"
    }

    private static func replace(pattern: String, in text: String, with template: String) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }

    private static func plainText(from markdown: String) -> String {
        var result = markdown
        result = replace(pattern: #"`([^`]+)`"#, in: result, with: "$1")
        result = replace(pattern: #"\[([^\]]+)\]\([^)]+\)"#, in: result, with: "$1")
        result = replace(pattern: #"\*\*([^*]+)\*\*"#, in: result, with: "$1")
        result = replace(pattern: #"__([^_]+)__"#, in: result, with: "$1")
        result = replace(pattern: #"\*([^*]+)\*"#, in: result, with: "$1")
        result = replace(pattern: #"_([^_]+)_"#, in: result, with: "$1")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uniqueSlug(for text: String, usedSlugs: inout [String: Int]) -> String {
        let base = slug(for: text)
        let count = usedSlugs[base, default: 0]
        usedSlugs[base] = count + 1
        return count == 0 ? base : "\(base)-\(count + 1)"
    }

    private static func slug(for text: String) -> String {
        var slug = ""
        var previousWasDash = false

        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                slug.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                slug.append("-")
                previousWasDash = true
            }
        }

        let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "section" : trimmed
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func cssNumber(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static let lightVarsCSS = """
    :root {
      --canvas: #f7f3ea;
      --paper: #fffdf8;
      --text: #24211d;
      --muted: #6f675d;
      --rule: #ded4c6;
      --accent: #0a7c84;
      --code-bg: #efe8dc;
      --quote-bg: #edf4f3;
      --quote-line: #0a7c84;
      --check-bg: #ffffff;
      --hl-kw: #0050b3;
      --hl-s: #1a6b1a;
      --hl-cm: #888;
      --hl-n: #a85400;
      --hl-tp: #006b72;
    }
    """

    private static let darkVarsCSS = """
    :root {
      --canvas: #17191a;
      --paper: #202222;
      --text: #eee9df;
      --muted: #b9afa3;
      --rule: #383634;
      --accent: #61c4ca;
      --code-bg: #2c2b29;
      --quote-bg: #1d2a2b;
      --quote-line: #61c4ca;
      --check-bg: #202222;
      --hl-kw: #7eb8f7;
      --hl-s: #7ec987;
      --hl-cm: #7a7a7a;
      --hl-n: #e09b55;
      --hl-tp: #61c4ca;
    }
    """

    private static let themeCSS = """
    :root {
      color-scheme: light dark;
      --font-scale: 1;
      --canvas: #f7f3ea;
      --paper: #fffdf8;
      --text: #24211d;
      --muted: #6f675d;
      --rule: #ded4c6;
      --accent: #0a7c84;
      --code-bg: #efe8dc;
      --quote-bg: #edf4f3;
      --quote-line: #0a7c84;
      --check-bg: #ffffff;
      --hl-kw: #0050b3;
      --hl-s: #1a6b1a;
      --hl-cm: #888;
      --hl-n: #a85400;
      --hl-tp: #006b72;
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --canvas: #17191a;
        --paper: #202222;
        --text: #eee9df;
        --muted: #b9afa3;
        --rule: #383634;
        --accent: #61c4ca;
        --code-bg: #2c2b29;
        --quote-bg: #1d2a2b;
        --quote-line: #61c4ca;
        --check-bg: #202222;
        --hl-kw: #7eb8f7;
        --hl-s: #7ec987;
        --hl-cm: #7a7a7a;
        --hl-n: #e09b55;
        --hl-tp: #61c4ca;
      }
    }

    * {
      box-sizing: border-box;
    }

    html {
      font-size: calc(16px * var(--font-scale));
    }

    body {
      margin: 0;
      min-height: 100vh;
      background:
        linear-gradient(90deg, rgba(0,0,0,.025) 1px, transparent 1px),
        linear-gradient(180deg, rgba(0,0,0,.02) 1px, transparent 1px),
        var(--canvas);
      background-size: 32px 32px;
      color: var(--text);
      font-family: 'Merriweather Sans', ui-sans-serif, system-ui, -apple-system, sans-serif;
      line-height: 1.68;
      -webkit-font-smoothing: antialiased;
      scroll-behavior: smooth;
    }

    .reading-layout {
      width: min(1180px, calc(100vw - 48px));
      margin: 0 auto;
      display: grid;
      grid-template-columns: minmax(180px, 240px) minmax(0, 820px);
      gap: 28px;
      align-items: start;
    }

    .reading-layout.no-toc {
      width: min(820px, calc(100vw - 48px));
      display: block;
    }

    .toc {
      position: sticky;
      top: 28px;
      max-height: calc(100vh - 56px);
      margin: 28px 0;
      padding: 18px 12px 18px 0;
      overflow: auto;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: var(--muted);
    }

    .toc-title {
      margin: 0 0 .75rem;
      padding-left: .75rem;
      color: var(--text);
      font-size: .76rem;
      font-weight: 720;
      letter-spacing: .08em;
      text-transform: uppercase;
    }

    .toc-links {
      display: grid;
      gap: .08rem;
      border-left: 1px solid color-mix(in srgb, var(--rule) 82%, transparent);
    }

    .toc-link {
      display: block;
      position: relative;
      padding: .42rem .65rem .42rem .85rem;
      border-radius: 0 7px 7px 0;
      color: var(--muted);
      font-size: .86rem;
      line-height: 1.32;
      text-decoration: none;
      text-wrap: balance;
    }

    .toc-link:hover {
      color: var(--accent);
      background: color-mix(in srgb, var(--accent) 10%, transparent);
    }

    .toc-link.active {
      color: var(--accent);
      background: color-mix(in srgb, var(--accent) 14%, transparent);
      box-shadow: inset 3px 0 0 var(--accent);
    }

    .toc-link.level-1 {
      color: var(--text);
      font-weight: 720;
      margin-top: .32rem;
      background: color-mix(in srgb, var(--paper) 54%, transparent);
      box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--rule) 58%, transparent);
    }

    .toc-link.level-1.active {
      color: var(--accent);
      background: color-mix(in srgb, var(--accent) 14%, transparent);
      box-shadow:
        inset 3px 0 0 var(--accent),
        inset 0 0 0 1px color-mix(in srgb, var(--accent) 32%, var(--rule));
    }

    .toc-link.level-2 {
      margin-left: 1.35rem;
      padding-left: .75rem;
      color: var(--muted);
      font-size: .8rem;
      font-weight: 520;
    }

    .toc-link.level-3 {
      margin-left: 2.35rem;
      padding-left: .72rem;
      color: color-mix(in srgb, var(--muted) 76%, var(--canvas));
      font-size: .75rem;
    }

    .toc-link.level-4,
    .toc-link.level-5,
    .toc-link.level-6 {
      margin-left: 3.1rem;
      padding-left: .7rem;
      color: color-mix(in srgb, var(--muted) 58%, var(--canvas));
      font-size: .7rem;
    }

    .document {
      width: 100%;
      min-height: calc(100vh - 56px);
      margin: 28px 0;
      padding: clamp(28px, 6vw, 64px);
      background: var(--paper);
      border: 1px solid var(--rule);
      border-radius: 8px;
      box-shadow: 0 18px 55px rgba(0,0,0,.12);
    }

    h1, h2, h3, h4, h5, h6 {
      color: var(--text);
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      line-height: 1.16;
      margin: 2.35em 0 .62em;
      letter-spacing: 0;
      scroll-margin-top: 28px;
    }

    h1 {
      font-size: 2.45rem;
      margin-top: 0;
      padding-bottom: .35em;
      border-bottom: 1px solid var(--rule);
    }

    h1:not(:first-child) {
      margin-top: 1.75em;
    }

    h2 {
      font-size: 1.65rem;
      padding-top: .25em;
    }

    h3 {
      font-size: 1.25rem;
    }

    p {
      margin: 0 0 1.05em;
      font-size: 1.08rem;
    }

    a {
      color: var(--accent);
      text-decoration-thickness: .08em;
      text-underline-offset: .18em;
    }

    ul, ol {
      margin: .25em 0 1.1em;
      padding-left: 1.45em;
    }

    li {
      margin: .58em 0;
      padding-left: .15em;
    }

    .task-list-item {
      list-style: none;
      margin-left: -1.45em;
      margin-top: .95em;
      margin-bottom: .95em;
      padding-left: 0;
      display: grid;
      grid-template-columns: 1.7em minmax(0, 1fr);
      column-gap: .72em;
      align-items: start;
    }

    .task-list-label {
      min-width: 0;
    }

    .task-list-checkbox {
      appearance: none;
      -webkit-appearance: none;
      width: 1.22em;
      height: 1.22em;
      margin: 0;
      border: 1.6px solid color-mix(in srgb, var(--muted) 72%, transparent);
      border-radius: 6px;
      background: var(--check-bg);
      box-shadow:
        inset 0 1px 0 rgba(255,255,255,.18),
        0 1px 2px rgba(0,0,0,.14);
      transform: translateY(.28em);
      display: inline-grid;
      place-content: center;
      opacity: 1;
    }

    .task-list-checkbox:checked {
      border-color: var(--accent);
      background: var(--accent);
      box-shadow:
        inset 0 1px 0 rgba(255,255,255,.26),
        0 2px 8px color-mix(in srgb, var(--accent) 28%, transparent);
    }

    .task-list-checkbox:checked::after {
      content: "";
      width: .36em;
      height: .68em;
      border: solid var(--paper);
      border-width: 0 .17em .17em 0;
      transform: rotate(42deg) translateY(-.05em);
    }

    blockquote {
      margin: 1.35em 0;
      padding: 1em 1.1em;
      border-left: 4px solid var(--quote-line);
      background: var(--quote-bg);
      border-radius: 0 8px 8px 0;
      color: var(--text);
    }

    blockquote p:last-child {
      margin-bottom: 0;
    }

    code {
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: .92em;
      background: var(--code-bg);
      border: 1px solid var(--rule);
      border-radius: 5px;
      padding: .12em .34em;
    }

    pre {
      margin: 1.25em 0 1.45em;
      padding: 1em 1.1em;
      overflow: auto;
      background: var(--code-bg);
      border: 1px solid var(--rule);
      border-radius: 8px;
    }

    pre code {
      display: block;
      padding: 0;
      border: 0;
      background: transparent;
      line-height: 1.55;
      white-space: pre;
    }

    pre code .kw { color: var(--hl-kw); font-weight: 600; }
    pre code .s  { color: var(--hl-s); }
    pre code .cm { color: var(--hl-cm); font-style: italic; }
    pre code .n  { color: var(--hl-n); }
    pre code .tp { color: var(--hl-tp); }

    table {
      border-collapse: collapse;
      width: 100%;
      margin: 1.35em 0;
      font-size: .94rem;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }

    th, td {
      padding: .52em .85em;
      text-align: left;
      border: 1px solid var(--rule);
      vertical-align: top;
    }

    th {
      background: var(--code-bg);
      font-weight: 640;
      font-size: .86rem;
      letter-spacing: .02em;
      white-space: nowrap;
    }

    tr:nth-child(even) td {
      background: color-mix(in srgb, var(--canvas) 40%, var(--paper));
    }

    hr {
      border: 0;
      border-top: 1px solid var(--rule);
      margin: 2em 0;
    }

    strong {
      font-weight: 720;
    }

    @media (max-width: 980px) {
      .reading-layout {
        width: calc(100vw - 32px);
        grid-template-columns: minmax(150px, 200px) minmax(0, 1fr);
        gap: 20px;
      }
    }

    @media (max-width: 640px) {
      .reading-layout {
        width: calc(100vw - 24px);
        grid-template-columns: minmax(132px, 168px) minmax(0, 1fr);
        gap: 16px;
      }

      .document {
        padding: 24px;
      }

      h1 {
        font-size: 2rem;
      }
    }
    """

    private static let highlightScript = #"""
    (function() {
      function esc(s) {
        return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
      }
      const KW = {
        swift: new Set('import class struct enum protocol extension func var let if else guard switch case default for while repeat in return break continue throws throw rethrows try catch async await static final public private internal fileprivate open mutating lazy override required convenience init deinit subscript get set willSet didSet self super nil true false typealias associatedtype where some any nonisolated isolated actor'.split(' ')),
        javascript: new Set('const let var function return if else for while do switch case default break continue class extends super import export from as async await try catch finally throw new this typeof instanceof void delete in of null undefined true false yield get set static'.split(' ')),
        typescript: new Set('const let var function return if else for while do switch case default break continue class extends implements interface type enum namespace import export from as async await try catch finally throw new this typeof instanceof void delete in of null undefined true false yield get set static private public protected readonly abstract declare keyof infer never unknown any string number boolean object symbol'.split(' ')),
        python: new Set('def class import from as return if elif else for while in not and or is None True False try except finally raise with yield lambda pass break continue global nonlocal async await del assert'.split(' ')),
        go: new Set('package import func var const type struct interface if else for range return break continue switch case default go defer select chan map nil true false error'.split(' ')),
        sql: new Set('SELECT FROM WHERE JOIN LEFT RIGHT INNER OUTER FULL CROSS ON AS AND OR NOT IN IS NULL ORDER BY GROUP HAVING LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE INDEX DROP ALTER ADD COLUMN PRIMARY KEY FOREIGN REFERENCES UNIQUE DEFAULT COUNT SUM AVG MIN MAX DISTINCT UNION ALL CASE WHEN THEN END ELSE WITH RETURNING'.split(' ')),
        bash: new Set('if then else elif fi for do done while until case esac function return exit echo local export source set unset shift true false'.split(' ')),
      };
      function detect(code) {
        if (/\b(SELECT|INSERT INTO|UPDATE\s+\w+\s+SET|CREATE TABLE)\b/i.test(code)) return 'sql';
        if (/^\s*package\s+\w+|:=\s*/m.test(code) && /\bfunc\b/.test(code)) return 'go';
        if (/\bfunc\s+\w+|\bguard\b|\bnil\b/.test(code) && /->|\.self\b|@MainActor/.test(code)) return 'swift';
        if (/\bfunc\s+\w+|\bvar\s+\w+\s*[:=]|\blet\s+\w+\s*[:=]/.test(code) && /\bguard\b|\bnil\b|->/.test(code)) return 'swift';
        if (/\bdef\s+\w+\s*\(|^from\s+\w+\s+import\b|^\s*import\s+\w+\s*$/m.test(code)) return 'python';
        if (/:\s*(string|number|boolean|void|never|any)\b|interface\s+\w+\s*\{|<[A-Z]\w*>/.test(code)) return 'typescript';
        if (/\bfunction\s+\w+|\bconst\s+\w+\s*=|\brequire\s*\(|=>\s*[{(]/.test(code)) return 'javascript';
        if (/^\s*#!(\/bin\/(bash|sh)|\/usr\/bin\/env\s+bash)/m.test(code)) return 'bash';
        return null;
      }
      function tokenize(code, lang) {
        const isSQL = lang === 'sql';
        const kw = KW[lang] || new Set();
        let out = '', i = 0;
        while (i < code.length) {
          const c = code[i];
          if (c === '/' && code[i+1] === '*') {
            const e = code.indexOf('*/', i+2); const end = e < 0 ? code.length : e+2;
            out += '<span class=cm>' + esc(code.slice(i,end)) + '</span>'; i = end; continue;
          }
          if ((c === '/' && code[i+1] === '/') || (c === '#' && (lang==='python'||lang==='bash'))) {
            const e = code.indexOf('\n', i); const end = e < 0 ? code.length : e;
            out += '<span class=cm>' + esc(code.slice(i,end)) + '</span>'; i = end; continue;
          }
          if (c === '-' && code[i+1] === '-' && isSQL) {
            const e = code.indexOf('\n', i); const end = e < 0 ? code.length : e;
            out += '<span class=cm>' + esc(code.slice(i,end)) + '</span>'; i = end; continue;
          }
          if (c === '"' || c === "'" || (c === '`' && (lang==='javascript'||lang==='typescript'))) {
            const q = c; let j = i+1;
            while (j < code.length) { if (code[j]==='\\') {j+=2;continue;} if (code[j]===q){j++;break;} j++; }
            out += '<span class=s>' + esc(code.slice(i,j)) + '</span>'; i = j; continue;
          }
          if (/[0-9]/.test(c) && (i===0||!/\w/.test(code[i-1]))) {
            let j = i; while (j<code.length && /[0-9a-fA-F._xXbBoOpPlLeEuU]/.test(code[j])) j++;
            out += '<span class=n>' + esc(code.slice(i,j)) + '</span>'; i = j; continue;
          }
          if (/[a-zA-Z_$]/.test(c)) {
            let j = i; while (j<code.length && /[\w$]/.test(code[j])) j++;
            const w = code.slice(i,j);
            if (kw.has(isSQL ? w.toUpperCase() : w)) out += '<span class=kw>' + esc(w) + '</span>';
            else if (/^[A-Z]/.test(w) && !isSQL) out += '<span class=tp>' + esc(w) + '</span>';
            else out += esc(w);
            i = j; continue;
          }
          out += esc(c); i++;
        }
        return out;
      }
      document.querySelectorAll('pre code').forEach(el => {
        const m = el.className.match(/language-(\w+)/);
        const lang = m ? m[1] : detect(el.textContent);
        if (lang) el.innerHTML = tokenize(el.textContent, lang);
      });
    })();
    """#

    private static let scrollSpyScript = """
    (() => {
      const links = Array.from(document.querySelectorAll('.toc-link[data-heading-id]'));
      const headings = links
        .map((link) => document.getElementById(link.dataset.headingId))
        .filter(Boolean);

      if (!links.length || !headings.length) return;

      const linkById = new Map(links.map((link) => [link.dataset.headingId, link]));
      let activeId = null;

      const setActive = (id) => {
        if (!id || id === activeId) return;
        activeId = id;
        links.forEach((link) => link.classList.toggle('active', link.dataset.headingId === id));
        const activeLink = linkById.get(id);
        if (activeLink) {
          activeLink.scrollIntoView({ block: 'nearest', inline: 'nearest' });
        }
      };

      const updateActive = () => {
        const offset = 96;
        let current = headings[0];

        for (const heading of headings) {
          if (heading.getBoundingClientRect().top <= offset) {
            current = heading;
          } else {
            break;
          }
        }

        setActive(current.id);
      };

      let ticking = false;
      const requestUpdate = () => {
        if (ticking) return;
        ticking = true;
        requestAnimationFrame(() => {
          updateActive();
          ticking = false;
        });
      };

      window.addEventListener('scroll', requestUpdate, { passive: true });
      window.addEventListener('resize', requestUpdate);
      links.forEach((link) => {
        link.addEventListener('click', () => setActive(link.dataset.headingId));
      });

      updateActive();
    })();
    """
}

private let sampleMarkdown = """
# Pretty Markdown

Pretty Markdown is a focused macOS Markdown viewer for reading local `.md` files with clean typography, automatic refresh, and a generated table of contents.

Open a Markdown file with **Command-O**, use the toolbar button, choose an item from **Open Recent**, or drop a `.md` file into the window.

> The viewer automatically reloads the current file when it changes on disk.

## App features

- **Open Recent** keeps quick access to the last files you opened.
- **Zoom** controls let you increase, decrease, or reset the reading size with Command-Plus, Command-Minus, and Command-0.
- **Appearance** can follow the system setting or switch between light and dark mode.
- **Contents** appears automatically when your document has headings.

## Markdown support

- Headings
- Paragraphs and links like [OpenAI](https://openai.com)
- Ordered and unordered lists
- Blockquotes
- Inline `code`
- Fenced code blocks
- Task lists
- Tables

## Table example

| Feature | Shortcut or access | Notes |
| --- | --- | --- |
| Open file | Command-O or toolbar | Supports Markdown and text files |
| Open Recent | File menu | Stores up to 10 recent documents |
| Zoom in | Command-Plus | Increases the reading font size |
| Zoom out | Command-Minus | Decreases the reading font size |
| Reset zoom | Command-0 | Returns to the default reading size |

## Task list example

- [x] Open a Markdown file
- [x] Review headings in Contents
- [ ] Adjust zoom for comfortable reading

```swift
struct Note {
    let title: String
    let body: String
}
```
"""
