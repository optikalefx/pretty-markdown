import Foundation

struct Heading {
    let level: Int
    let title: String
    let id: String
}

struct RenderedContent {
    let body: String
    let headings: [Heading]
    let frontMatter: [FrontMatterField]
}

/// Converts Markdown source into body HTML plus the headings needed for the
/// table of contents. Pure text-in/text-out — no WebKit or page chrome here.
enum MarkdownParser {
    static func parse(_ markdown: String) -> RenderedContent {
        let frontMatter: [FrontMatterField]
        let source: String
        if let split = FrontMatterParser.split(markdown) {
            frontMatter = split.fields
            source = split.body
        } else {
            frontMatter = []
            source = markdown
        }

        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
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
            // A lone image on its own line becomes a block (optionally a
            // <figure> with caption / size / float), matching seanclark.dev.
            if paragraph.count == 1, let block = loneImageBlock(from: paragraph[0]) {
                html.append(block)
            } else {
                html.append("<p>\(inlineHTML(paragraph.joined(separator: " ")))</p>")
            }
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
                    html.append("<pre><code\(cls)>\(codeLines.joined(separator: "\n").htmlEscaped)</code></pre>")
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
            html.append("<pre><code>\(codeLines.joined(separator: "\n").htmlEscaped)</code></pre>")
        }
        flushFlow()
        return RenderedContent(body: html.joined(separator: "\n"), headings: headings, frontMatter: frontMatter)
    }

    private static func inlineHTML(_ text: String) -> String {
        var result = text.htmlEscaped
        // Images run before the other inline rules so `*`/`_` inside alt text or
        // file names aren't mistaken for emphasis, and before links so that an
        // image-as-link's inner `[…](…)` isn't consumed by the link rule.
        result = replaceInlineImages(result)
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

    // MARK: - Images

    // A whole line that is nothing but a linked image or a bare image. Operates
    // on the raw (unescaped) line, so titles are delimited by literal quotes.
    private static let loneLinkedImage = #"^\[!\[([^\]]*)\]\(\s*(\S+?)(?:\s+"([^"]*)")?\s*\)\]\(\s*(\S+?)\s*\)$"#
    private static let loneImage = #"^!\[([^\]]*)\]\(\s*(\S+?)(?:\s+"([^"]*)")?\s*\)$"#

    // Inline forms, matched inside already-escaped text (so a title's quotes
    // appear as `&quot;`). Used for images that sit within a run of prose.
    private static let inlineLinkedImage = #"\[!\[([^\]]*)\]\(([^)\s]+)(?:\s+&quot;(.*?)&quot;)?\)\]\(([^)\s]+)\)"#
    private static let inlineImage = #"!\[([^\]]*)\]\(([^)\s]+)(?:\s+&quot;(.*?)&quot;)?\)"#

    /// If `rawLine` is exactly one image (optionally wrapped in a link), returns
    /// the block-level HTML for it — a `<figure>` when there's a caption, size,
    /// or float hint, otherwise a bare `<img>` / linked `<img>`. Returns nil
    /// when the line is anything else.
    private static func loneImageBlock(from rawLine: String) -> String? {
        if let g = fullMatch(rawLine, pattern: loneLinkedImage) {
            return imageBlock(alt: g[1], src: g[2], title: g[3], href: g[4])
        }
        if let g = fullMatch(rawLine, pattern: loneImage) {
            return imageBlock(alt: g[1], src: g[2], title: g[3], href: nil)
        }
        return nil
    }

    /// Builds block-level image HTML from raw (unescaped) pieces, mirroring the
    /// seanclark.dev rehype rules: bare images stay bare, plain linked images
    /// stay a bare `<a><img></a>`, and anything with a caption, size, or float
    /// hint is wrapped in a `<figure>` that carries the layout classes.
    private static func imageBlock(alt rawAlt: String, src: String, title: String, href: String?) -> String {
        let (classes, cleanedAlt) = imageHints(from: rawAlt)
        let classAttr = classes.isEmpty ? "" : " class=\"\(classes.joined(separator: " ").htmlEscaped)\""
        let srcAttr = src.htmlEscaped
        let altAttr = cleanedAlt.htmlEscaped
        let linked = href != nil

        // Bare image, no caption: layout classes ride on the <img> itself.
        if !linked && title.isEmpty {
            return "<img src=\"\(srcAttr)\" alt=\"\(altAttr)\"\(classAttr)>"
        }

        let img = "<img src=\"\(srcAttr)\" alt=\"\(altAttr)\">"
        let content = href.map { "<a href=\"\($0.htmlEscaped)\">\(img)</a>" } ?? img

        // Plain linked image with nothing special: no wrapper needed.
        if linked && title.isEmpty && classes.isEmpty {
            return content
        }

        // Otherwise wrap in a <figure> so the layout classes and optional caption
        // live on a block-level container.
        var inner = content
        if !title.isEmpty {
            inner += "<figcaption>\(title.htmlEscaped)</figcaption>"
        }
        return "<figure\(classAttr)>\(inner)</figure>"
    }

    /// Replaces images that appear mid-paragraph. These always render inline as
    /// `<img>` (or a linked `<img>`) — captions/figures are reserved for images
    /// that stand alone on their own line.
    private static func replaceInlineImages(_ escapedText: String) -> String {
        var result = regexReplace(escapedText, inlineLinkedImage) { g in
            inlineImageTag(alt: g[1], src: g[2], href: g[4])
        }
        result = regexReplace(result, inlineImage) { g in
            inlineImageTag(alt: g[1], src: g[2], href: nil)
        }
        return result
    }

    /// Builds inline `<img>` HTML from already-escaped pieces.
    private static func inlineImageTag(alt: String, src: String, href: String?) -> String {
        let (classes, cleanedAlt) = imageHints(from: alt)
        let classAttr = classes.isEmpty ? "" : " class=\"\(classes.joined(separator: " "))\""
        let img = "<img src=\"\(src)\" alt=\"\(cleanedAlt)\"\(classAttr)>"
        return href.map { "<a href=\"\($0)\">\(img)</a>" } ?? img
    }

    /// Pulls `#small`/`#medium`/`#large`/`#left`/`#right` hints out of alt text,
    /// returning the CSS classes to apply and the alt text with hints stripped.
    /// Floated images default to `#small` when no explicit size is given.
    private static func imageHints(from alt: String) -> (classes: [String], cleanedAlt: String) {
        guard let regex = try? NSRegularExpression(pattern: #"#(small|medium|large|left|right)\b"#) else {
            return ([], alt)
        }
        let ns = alt as NSString
        let range = NSRange(location: 0, length: ns.length)
        var classes: [String] = []
        for m in regex.matches(in: alt, range: range) {
            classes.append("img-\(ns.substring(with: m.range(at: 1)))")
        }
        var cleaned = regex.stringByReplacingMatches(in: alt, range: range, withTemplate: "")
        cleaned = cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        let floated = classes.contains("img-left") || classes.contains("img-right")
        let sized = classes.contains { $0 == "img-small" || $0 == "img-medium" || $0 == "img-large" }
        if floated && !sized { classes.append("img-small") }
        return (classes, cleaned)
    }

    /// Whole-string regex match: returns the capture groups (index 0 is the full
    /// match) only when the pattern consumes the entire string, else nil. A group
    /// that didn't participate comes back as "".
    private static func fullMatch(_ text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.range.length == ns.length else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    /// Rewrites every match of `pattern` in `text` using `transform`, which
    /// receives the capture groups (index 0 is the full match; non-participating
    /// groups are ""). Unlike template replacement this allows per-match logic.
    private static func regexReplace(_ text: String, _ pattern: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = 0
        for m in matches {
            result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            let groups = (0..<m.numberOfRanges).map { i -> String in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            result += transform(groups)
            cursor = m.range.location + m.range.length
        }
        result += ns.substring(from: cursor)
        return result
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
}
