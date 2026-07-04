import Foundation

struct Heading {
    let level: Int
    let title: String
    let id: String
}

struct RenderedContent {
    let body: String
    let headings: [Heading]
}

/// Converts Markdown source into body HTML plus the headings needed for the
/// table of contents. Pure text-in/text-out — no WebKit or page chrome here.
enum MarkdownParser {
    static func parse(_ markdown: String) -> RenderedContent {
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
        return RenderedContent(body: html.joined(separator: "\n"), headings: headings)
    }

    private static func inlineHTML(_ text: String) -> String {
        var result = text.htmlEscaped
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
}
