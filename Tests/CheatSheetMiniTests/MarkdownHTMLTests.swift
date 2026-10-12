import XCTest
@testable import CheatSheetMini

final class MarkdownHTMLTests: XCTestCase {
    private let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"50\"><rect width=\"100\" height=\"50\"/></svg>".utf8)
    private func fixture(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("electronic_work"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try svg.write(to: root.appendingPathComponent("electronic_work/Pch-MOSFET-AS-Diode.svg"))
        try svg.write(to: root.appendingPathComponent("image.svg"))
        try body(root)
    }
    func testRequestedExampleAndImageOrder() throws {
        try fixture { root in
            let html = try markdownPreviewHTML("""
            ## Pch MOSFETをダイオードとして使う

            - GATE : SOURCE につなぐ

            <img src="./electronic_work/Pch-MOSFET-AS-Diode.svg" width="80%">

            後の本文
            """, relativeTo: root.appendingPathComponent("electronic_work.md"))
            XCTAssertTrue(html.contains("data:image/svg+xml;base64,\(svg.base64EncodedString())"))
            XCTAssertTrue(html.contains("width: 80%; max-width: 100%; height: auto"))
            XCTAssertTrue(html.contains("<li>GATE : SOURCE につなぐ</li>"))
            XCTAssertLessThan(html.range(of: "<img")!.lowerBound, html.range(of: "後の本文")!.lowerBound)
            let multiple = try markdownPreviewHTML("前 <img src='image.svg' alt='一'> 中 <img src='image.svg' alt='二'> 後", relativeTo: root.appendingPathComponent("doc.md"))
            XCTAssertEqual(multiple.components(separatedBy: "<img").count - 1, 2)
            XCTAssertLessThan(multiple.range(of: "alt=\"一\"")!.lowerBound, multiple.range(of: "alt=\"二\"")!.lowerBound)
            let block = try markdownPreviewHTML("<img src='image.svg'>\n<img src='image.svg'>", relativeTo: root.appendingPathComponent("doc.md"))
            XCTAssertEqual(block.components(separatedBy: "<img").count - 1, 2)
        }
    }
    func testAttributesAndEntities() throws {
        try fixture { root in
            try svg.write(to: root.appendingPathComponent("a&b.svg"))
            let html = try markdownPreviewHTML("<IMG TITLE='a > b &quot; c' WIDTH='320' SRC = 'a&amp;b.svg' alt='&lt;test&gt;' onerror='alert(1)' style='bad' srcset='bad'>", relativeTo: root.appendingPathComponent("doc.md"))
            XCTAssertTrue(html.contains("data:image/svg+xml;base64,"))
            XCTAssertTrue(html.contains("title=\"a &gt; b &quot; c\""))
            XCTAssertTrue(html.contains("alt=\"&lt;test&gt;\""))
            XCTAssertTrue(html.contains("width: 320px"))
            for forbidden in ["onerror", "alert(1)", "srcset", "bad"] { XCTAssertFalse(html.contains(forbidden)) }
            let numeric = try markdownPreviewHTML("<img src='image&#46;svg'>", relativeTo: root.appendingPathComponent("doc.md"))
            XCTAssertTrue(numeric.contains("data:image/svg+xml;base64,"))
        }
    }
    func testWidthsAndInvalidTags() throws {
        try fixture { root in
            for width in ["80%", "0.5%", "100%", "320"] {
                let html = try markdownPreviewHTML("<img src='image.svg' width='\(width)'>", relativeTo: root.appendingPathComponent("doc.md"))
                XCTAssertTrue(html.contains("style=\"width:"), width)
            }
            for width in ["", "0", "-1", "0%", "101%", "NaN%", "80%; color:red", "calc(100%)"] {
                let html = try markdownPreviewHTML("<img src='image.svg' width='\(width)'>", relativeTo: root.appendingPathComponent("doc.md"))
                XCTAssertTrue(html.contains("data:image/svg+xml;base64,"), width)
                XCTAssertFalse(html.contains("style="), width)
            }
            for tag in ["<img src='image.svg' src='other.svg'>", "<img src=image.svg>", "<img src='image.svg'broken>", "<img src='image.svg>"] {
                XCTAssertFalse(try markdownPreviewHTML(tag, relativeTo: root.appendingPathComponent("doc.md")).contains("data:image/"), tag)
            }
        }
    }
    func testCodeAndOtherHTMLStaySuppressed() throws {
        try fixture { root in
            for markdown in [
                "```html\n<img src='image.svg'>\n```", "    <img src='image.svg'>", "`<img src='image.svg'>`",
                "<!-- <img src='image.svg'> -->", "<script>\nvar x = \"<img src='image.svg'>\";\n</script>",
                "text <script>\"<img src='image.svg'>\"</script> end", "<iframe><img src='image.svg'></iframe>"
            ] {
                let html = try markdownPreviewHTML(markdown, relativeTo: root.appendingPathComponent("doc.md"))
                XCTAssertFalse(html.contains("<img"), markdown)
                XCTAssertFalse(html.contains("data:image/"), markdown)
                XCTAssertFalse(html.contains("<script"), markdown)
                XCTAssertFalse(html.contains("<iframe"), markdown)
            }
            let code = try markdownPreviewHTML("`<img src='image.svg'>`", relativeTo: root.appendingPathComponent("doc.md"))
            XCTAssertTrue(code.contains("<code>&lt;img"))
        }
    }
    func testMissingUnsupportedAndOutOfScopeImages() throws {
        try fixture { root in
            try Data("not an image".utf8).write(to: root.appendingPathComponent("file.txt"))
            for source in ["missing.svg", "file.txt", "../image.svg", "/tmp/image.svg", "file:///tmp/image.svg", "javascript:alert(1)", "https://example.com/image.svg", "data:image/svg+xml;base64,AAAA", "%2e%2e/image.svg"] {
                let html = try markdownPreviewHTML("前\n\n<img src='\(source)'>\n\n後", relativeTo: root.appendingPathComponent("doc.md"))
                XCTAssertFalse(html.contains("data:image/"), source)
                XCTAssertTrue(html.contains("前"))
                XCTAssertTrue(html.contains("後"))
            }
            let external = try markdownPreviewHTML("![image](https://example.com/image.png)", relativeTo: root.appendingPathComponent("doc.md"))
            XCTAssertTrue(external.contains("src=\"https://example.com/image.png\""))
        }
    }
    func testSizeBoundaryAndRelativeFolders() throws {
        try fixture { root in
            let file = root.appendingPathComponent("large.svg")
            try Data(repeating: 65, count: 15_000_000).write(to: file)
            let tooLarge = try markdownPreviewHTML("<img src='large.svg'>", relativeTo: root.appendingPathComponent("doc.md"))
            XCTAssertFalse(tooLarge.contains("data:image/"))
            try Data(repeating: 65, count: 14_999_999).write(to: file)
            XCTAssertTrue(try markdownPreviewHTML("<img src='large.svg'>", relativeTo: root.appendingPathComponent("doc.md")).contains("data:image/svg+xml;base64,"))
            let nested = root.appendingPathComponent("other")
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            let other = Data("<svg><!-- other --></svg>".utf8)
            try other.write(to: nested.appendingPathComponent("image.svg"))
            let first = try markdownPreviewHTML("![image](image.svg)", relativeTo: root.appendingPathComponent("doc.md"))
            let second = try markdownPreviewHTML("<img src='image.svg'>", relativeTo: nested.appendingPathComponent("doc.md"))
            XCTAssertTrue(first.contains(svg.base64EncodedString()))
            XCTAssertTrue(second.contains(other.base64EncodedString()))
            let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aL1sAAAAASUVORK5CYII=")!
            try png.write(to: root.appendingPathComponent("image.png"))
            XCTAssertTrue(try markdownPreviewHTML("<img src='image.png'>", relativeTo: root.appendingPathComponent("doc.md")).contains("data:image/png;base64,\(png.base64EncodedString())"))
        }
    }
}
