import Foundation

struct FrontMatterField {
    let key: String
    let value: FrontMatterValue
}

enum FrontMatterValue {
    case scalar(String)
    case list([String])
}

/// Extracts a leading YAML front matter block — a `---` fence on the very
/// first line closed by a later `---` (or `...`) line. Understands just enough
/// YAML for document metadata: plain and quoted scalars, block scalars
/// (`>`/`>-` folded, `|`/`|-` literal), string lists, and one level of nested
/// mappings (flattened to dotted keys like `metadata.type`).
enum FrontMatterParser {
    static func split(_ markdown: String) -> (fields: [FrontMatterField], body: String)? {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        guard let closing = lines.dropFirst().firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed == "---" || trimmed == "..."
        }) else { return nil }

        let fields = parseFields(Array(lines[1..<closing]))
        guard !fields.isEmpty else { return nil }
        return (fields, lines[(closing + 1)...].joined(separator: "\n"))
    }

    private static func parseFields(_ lines: [String]) -> [FrontMatterField] {
        var fields: [FrontMatterField] = []
        var index = 0

        while index < lines.count {
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            index += 1

            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), indent(of: raw) == 0,
                  let (key, rest) = keyValue(from: trimmed) else { continue }

            if rest.hasPrefix(">") || rest.hasPrefix("|") {
                let block = collectIndented(lines, from: &index)
                let text = joinBlock(block, folded: rest.hasPrefix(">"))
                fields.append(FrontMatterField(key: key, value: .scalar(text)))
            } else if rest.isEmpty {
                let block = collectIndented(lines, from: &index)
                fields.append(contentsOf: nestedFields(for: key, block: block))
            } else {
                fields.append(FrontMatterField(key: key, value: .scalar(unquote(rest))))
            }
        }

        return fields
    }

    /// A key with no inline value introduces either a list, a nested mapping,
    /// or nothing. Nested mapping keys are flattened as `parent.child`.
    private static func nestedFields(for key: String, block: [String]) -> [FrontMatterField] {
        let items = block.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !items.isEmpty else {
            return [FrontMatterField(key: key, value: .scalar(""))]
        }

        if items.allSatisfy({ $0.hasPrefix("- ") || $0 == "-" }) {
            let values = items.map { unquote(String($0.dropFirst(1)).trimmingCharacters(in: .whitespaces)) }
            return [FrontMatterField(key: key, value: .list(values))]
        }

        var fields: [FrontMatterField] = []
        for item in items {
            guard let (childKey, rest) = keyValue(from: item) else { continue }
            fields.append(FrontMatterField(key: "\(key).\(childKey)", value: .scalar(unquote(rest))))
        }
        return fields.isEmpty ? [FrontMatterField(key: key, value: .scalar(items.joined(separator: " ")))] : fields
    }

    /// Consumes the run of lines indented under the current key (blank lines
    /// included) and advances the caller's index past them.
    private static func collectIndented(_ lines: [String], from index: inout Int) -> [String] {
        var block: [String] = []
        while index < lines.count {
            let line = lines[index]
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            guard isBlank || indent(of: line) > 0 else { break }
            block.append(line)
            index += 1
        }
        while block.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            block.removeLast()
        }
        return block
    }

    private static func joinBlock(_ block: [String], folded: Bool) -> String {
        let trimmed = block.map { $0.trimmingCharacters(in: .whitespaces) }
        guard folded else { return trimmed.joined(separator: "\n") }
        // Folded scalar: single newlines become spaces, blank lines stay breaks.
        var paragraphs: [[String]] = [[]]
        for line in trimmed {
            if line.isEmpty {
                if !(paragraphs.last?.isEmpty ?? true) { paragraphs.append([]) }
            } else {
                paragraphs[paragraphs.count - 1].append(line)
            }
        }
        return paragraphs.filter { !$0.isEmpty }.map { $0.joined(separator: " ") }.joined(separator: "\n")
    }

    private static func keyValue(from line: String) -> (key: String, rest: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !key.contains(" ") else { return nil }
        let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (key, rest)
    }

    private static func unquote(_ text: String) -> String {
        for quote in ["\"", "'"] where text.count >= 2 && text.hasPrefix(quote) && text.hasSuffix(quote) {
            return String(text.dropFirst().dropLast())
        }
        return text
    }

    private static func indent(of line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }
}
