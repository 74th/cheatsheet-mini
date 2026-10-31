import XCTest
@testable import CheatSheetMini

final class SearchRankTests: XCTestCase {
    private func entry(_ file: String, _ heading: String) -> Entry {
        let url = URL(fileURLWithPath: "/sheets/\(file).md")
        return Entry(id: "\(url.path)#\(heading)", fileName: file, documentTitle: file,
                     heading: heading, markdown: "## \(heading)", fileURL: url)
    }

    private lazy var entries = [
        entry("python", "HTTPサーバーを立てる"),
        entry("python", "venvを作る"),
        entry("python-extra", "HTTPクライアント"),
        entry("curl", "HTTPヘッダーを表示する"),
    ]

    func testColonLimitsToExactFileName() {
        XCTAssertEqual(rank("python:HTTP", entries: entries).map(\.heading), ["HTTPサーバーを立てる"])
        XCTAssertEqual(rank("Python:http", entries: entries).map(\.heading), ["HTTPサーバーを立てる"])
        XCTAssertEqual(Set(rank("python:", entries: entries).map(\.heading)), ["HTTPサーバーを立てる", "venvを作る"])
        XCTAssertTrue(rank("pyth:HTTP", entries: entries).isEmpty)
    }

    func testDotKeepsLooseFileMatch() {
        XCTAssertEqual(Set(rank("python.HTTP", entries: entries).map(\.heading)), ["HTTPサーバーを立てる", "HTTPクライアント"])
    }

    func testFirstSeparatorDecidesMode() {
        let scoped = [entry("python", "http.server"), entry("python-extra", "http.server")]
        XCTAssertEqual(rank("python:http.server", entries: scoped).map(\.fileName), ["python"])
    }
}

final class BodySearchTests: XCTestCase {
    private func entry(_ file: String, _ heading: String, _ body: String) -> Entry {
        let url = URL(fileURLWithPath: "/sheets/\(file).md")
        return Entry(id: "\(url.path)#\(heading)", fileName: file, documentTitle: file,
                     heading: heading, markdown: "## \(heading)\n\n\(body)", fileURL: url)
    }

    func testBodyMatchesRankAfterHeadingMatches() {
        let entries = [
            entry("python", "venvを作る", "python -m venv .venv"),
            entry("python", "サーバーを立てる", "python -m http.server 8000"),
            entry("curl", "HTTPヘッダーを表示する", "curl -I"),
        ]
        XCTAssertEqual(rank("http", entries: entries).map(\.heading), ["HTTPヘッダーを表示する", "サーバーを立てる"])
        XCTAssertEqual(rank("python:HTTP", entries: entries).map(\.heading), ["サーバーを立てる"])
        XCTAssertTrue(rank("存在しない語", entries: entries).isEmpty)
    }

    func testBodyRequiresSubstringNotFuzzy() {
        let entries = [entry("git", "ブランチ", "git switch -c topic")]
        XCTAssertEqual(rank("switch -c", entries: entries).count, 1)
        XCTAssertTrue(rank("swxtch", entries: entries).isEmpty)
    }
}
