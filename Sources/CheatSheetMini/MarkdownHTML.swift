import Foundation
import Down
import libcmark

// Keep cmark's safe rendering, replacing only recognized HTML images with
// application-generated custom nodes. Code nodes never enter this path.
func markdownPreviewHTML(_ markdown: String, relativeTo fileURL: URL) throws -> String {
    let tree = try Down(markdownString: markdown).toAST()
    defer { cmark_node_free(tree) }
    var images = HTMLImageReader()
    func visit(_ parent: CMarkNode) {
        var child = cmark_node_first_child(parent)
        while let node = child {
            child = cmark_node_next(node)
            let type = cmark_node_get_type(node)
            if type == CMARK_NODE_HTML_BLOCK || type == CMARK_NODE_HTML_INLINE,
               let literal = cmark_node_get_literal(node) {
                let html = images.read(String(cString: literal))
                if !html.isEmpty, let replacement = cmark_node_new(
                    type == CMARK_NODE_HTML_BLOCK ? CMARK_NODE_CUSTOM_BLOCK : CMARK_NODE_CUSTOM_INLINE
                ) {
                    cmark_node_set_on_enter(replacement, html)
                    cmark_node_insert_before(node, replacement)
                    cmark_node_unlink(node)
                    cmark_node_free(node)
                }
            } else {
                visit(node)
            }
        }
    }
    visit(tree)
    return embedLocalImages(in: try DownHTMLRenderer.astToHTML(tree), relativeTo: fileURL)
}

private struct HTMLImageReader {
    // Raw-text elements can span several inline HTML nodes.
    private var rawElement: String?
    private let rawElements: Set<String> = ["script", "style", "iframe", "textarea", "title", "xmp", "plaintext", "noembed", "noframes"]

    mutating func read(_ html: String) -> String {
        let chars = Array(html)
        var index = 0
        var output = ""
        while index < chars.count {
            guard chars[index] == "<" else { index += 1; continue }
            if String(chars[index...]).hasPrefix("<!--") {
                let remainder = String(chars[index...])
                if let end = remainder.range(of: "-->") {
                    index += remainder.distance(from: remainder.startIndex, to: end.upperBound)
                } else { break }
                continue
            }
            let start = index
            index += 1
            var quote: Character?
            while index < chars.count {
                let character = chars[index]
                if let delimiter = quote {
                    if character == delimiter { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == ">" { break }
                index += 1
            }
            guard index < chars.count else { break }
            let tag = String(chars[(start + 1)..<index])
            index += 1
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            let closing = trimmed.hasPrefix("/")
            let nameText = closing ? String(trimmed.dropFirst()) : trimmed
            let name = String(nameText.prefix { $0.isASCII && ($0.isLetter || $0.isNumber) }).lowercased()
            if let raw = rawElement {
                if closing && name == raw { rawElement = nil }
                continue
            }
            if !closing && rawElements.contains(name) { rawElement = name; continue }
            guard !closing, name == "img", let attributes = parseImageAttributes(trimmed),
                  let source = attributes["src"], source.quoted else { continue }
            let src = decodeHTMLEntities(source.value)
            guard let decoded = src.removingPercentEncoding,
                  !decoded.isEmpty, !decoded.hasPrefix("/"), !decoded.contains(":"),
                  !decoded.contains("\\"), !decoded.components(separatedBy: "/").contains("..") else { continue }
            output += "<img src=\"\(escapeHTML(src))\""
            for key in ["alt", "title"] {
                if let attribute = attributes[key], attribute.quoted {
                    output += " \(key)=\"\(escapeHTML(decodeHTMLEntities(attribute.value)))\""
                }
            }
            if let width = attributes["width"], width.quoted,
               let normalized = imageWidth(decodeHTMLEntities(width.value)) {
                output += " style=\"width: \(normalized); max-width: 100%; height: auto\""
            }
            output += ">"
        }
        return output
    }
}

private struct HTMLAttribute {
    let value: String
    let quoted: Bool
}

// Consume the complete tag; an invalid or duplicate attribute rejects the tag.
private func parseImageAttributes(_ tag: String) -> [String: HTMLAttribute]? {
    let chars = Array(tag)
    var index = 3
    var result: [String: HTMLAttribute] = [:]
    func whitespace() { while index < chars.count && chars[index].isWhitespace { index += 1 } }
    while index < chars.count {
        guard chars[index].isWhitespace || chars[index] == "/" else { return nil }
        whitespace()
        if index == chars.count { break }
        if chars[index] == "/" { return index == chars.count - 1 ? result : nil }
        let start = index
        while index < chars.count && !chars[index].isWhitespace && !"=/'\"<>`".contains(chars[index]) { index += 1 }
        guard index > start else { return nil }
        let name = String(chars[start..<index]).lowercased()
        guard result[name] == nil else { return nil }
        let afterName = index
        whitespace()
        guard index < chars.count && chars[index] == "=" else {
            result[name] = HTMLAttribute(value: "", quoted: false)
            index = afterName
            continue
        }
        index += 1
        whitespace()
        guard index < chars.count else { return nil }
        let quoted = chars[index] == "'" || chars[index] == "\""
        let value: String
        if quoted {
            let delimiter = chars[index]
            index += 1
            let valueStart = index
            while index < chars.count && chars[index] != delimiter { index += 1 }
            guard index < chars.count else { return nil }
            value = String(chars[valueStart..<index])
            index += 1
        } else {
            let valueStart = index
            while index < chars.count && !chars[index].isWhitespace { index += 1 }
            value = String(chars[valueStart..<index])
            guard !value.isEmpty, !value.contains(where: { "'\"<=`>".contains($0) }) else { return nil }
        }
        result[name] = HTMLAttribute(value: value, quoted: quoted)
    }
    return result
}

private func imageWidth(_ value: String) -> String? {
    if value.hasSuffix("%") {
        let number = String(value.dropLast())
        guard number.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let width = Double(number), width > 0, width <= 100 else { return nil }
        return "\(number)%"
    }
    guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }),
          let width = Int(value), width > 0 else { return nil }
    return "\(width)px"
}

private func escapeHTML(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

func decodeHTMLEntities(_ value: String) -> String {
    // cmark already has the HTML5 named/numeric entity table. Parse each entity
    // alone so other attribute characters are never interpreted as Markdown.
    let regex = try! NSRegularExpression(pattern: #"&(?:#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]+);"#)
    let source = value as NSString
    var result = value
    for match in regex.matches(in: value, range: NSRange(location: 0, length: source.length)).reversed() {
        let entity = source.substring(with: match.range)
        guard let tree = try? Down(markdownString: entity).toAST() else { continue }
        defer { cmark_node_free(tree) }
        if let paragraph = cmark_node_first_child(tree), let text = cmark_node_first_child(paragraph),
           let literal = cmark_node_get_literal(text), let range = Range(match.range, in: result) {
            result.replaceSubrange(range, with: String(cString: literal))
        }
    }
    return result
}
