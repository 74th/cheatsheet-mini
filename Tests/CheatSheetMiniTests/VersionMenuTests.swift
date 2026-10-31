import XCTest
@testable import CheatSheetMini

final class VersionMenuTests: XCTestCase {
    func testShowsShortVersionFromInfoPlist() {
        XCTAssertEqual(versionMenuTitle(infoDictionary: ["CFBundleShortVersionString": "0.2.0"]), "バージョン 0.2.0")
    }

    func testFallsBackWithoutInfoPlist() {
        XCTAssertEqual(versionMenuTitle(infoDictionary: nil), "バージョン 不明（開発ビルド）")
        XCTAssertEqual(versionMenuTitle(infoDictionary: ["CFBundleShortVersionString": ""]), "バージョン 不明（開発ビルド）")
    }
}
