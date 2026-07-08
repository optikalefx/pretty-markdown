import Foundation

/// Wraps parsed Markdown in the full HTML page: theme CSS, table of contents,
/// and the highlight/scroll-spy scripts. The CSS and JS live as real files in
/// Resources/ and are bundled via SwiftPM (`Bundle.module`).
enum MarkdownHTMLRenderer {
    static func render(
        markdown: String,
        title: String,
        appearanceMode: AppearanceMode = .system,
        fontScale: Double = 1.0
    ) -> String {
        let rendered = MarkdownParser.parse(markdown)
        let layoutClass = rendered.headings.isEmpty ? "reading-layout no-toc" : "reading-layout"
        let themeAttribute: String
        switch appearanceMode {
        case .system: themeAttribute = ""
        case .light:  themeAttribute = " data-theme=\"light\""
        case .dark:   themeAttribute = " data-theme=\"dark\""
        }
        return """
        <!doctype html>
        <html\(themeAttribute) style="--font-scale: \(cssNumber(fontScale))">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(title.htmlEscaped)</title>
          <link rel="preconnect" href="https://fonts.googleapis.com">
          <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
          <link href="https://fonts.googleapis.com/css2?family=Merriweather+Sans:ital,wght@0,300..800;1,300..800&display=swap" rel="stylesheet">
          <style>\(themeCSS)</style>
        </head>
        <body>
          <div class="\(layoutClass)">
            \(tocHTML(from: rendered.headings))
            <main class="document">
              \(frontMatterHTML(from: rendered.frontMatter))
              \(rendered.body)
            </main>
          </div>
          <script>\(scrollSpyScript)</script>
          <script>\(highlightScript)</script>
        </body>
        </html>
        """
    }

    private static func frontMatterHTML(from fields: [FrontMatterField]) -> String {
        guard !fields.isEmpty else { return "" }
        let rows = fields.map { field -> String in
            let valueHTML: String
            let wide: Bool
            switch field.value {
            case .scalar(let text):
                wide = text.count > 72 || text.contains("\n")
                valueHTML = text.isEmpty ? "<span class=\"front-matter-empty\">—</span>" : text.htmlEscaped
            case .list(let items):
                wide = items.reduce(0) { $0 + $1.count } > 60
                valueHTML = items.map { "<span class=\"front-matter-chip\">\($0.htmlEscaped)</span>" }.joined()
            }
            let cls = wide ? " front-matter-field-wide" : ""
            return """
            <div class="front-matter-field\(cls)"><dt>\(field.key.htmlEscaped)</dt><dd>\(valueHTML)</dd></div>
            """
        }.joined(separator: "\n")

        return """
        <header class="front-matter" aria-label="Document metadata">
          <div class="front-matter-title">Front matter</div>
          <dl class="front-matter-grid">
            \(rows)
          </dl>
        </header>
        """
    }

    private static func tocHTML(from headings: [Heading]) -> String {
        guard !headings.isEmpty else { return "" }
        let links = headings.map { heading in
            """
            <a class="toc-link level-\(heading.level)" href="#\(heading.id)" data-heading-id="\(heading.id)">\(heading.title.htmlEscaped)</a>
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

    private static func cssNumber(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static let themeCSS = bundledResource("theme", extension: "css")
    private static let highlightScript = bundledResource("highlight", extension: "js")
    private static let scrollSpyScript = bundledResource("scrollspy", extension: "js")

    private static func bundledResource(_ name: String, extension ext: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Missing bundled resource \(name).\(ext) — the SwiftPM resource bundle was not packaged next to the executable (see package.sh).")
        }
        return text
    }
}
