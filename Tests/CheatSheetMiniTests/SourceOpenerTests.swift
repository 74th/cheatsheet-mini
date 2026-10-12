import XCTest
@testable import CheatSheetMini

final class SourceOpenerTests: XCTestCase {
    private func fixture() throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("editor")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (directory.appendingPathComponent("日本語 'notes' and spaces.md"), executable)
    }

    @MainActor func testSettingsPersistenceAndDraftReset() throws {
        let name = "CheatSheetMiniSourceOpenTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SourceOpenSettings(defaults: defaults)
        XCTAssertEqual(settings.command, "")
        try settings.apply("code $file")
        XCTAssertEqual(SourceOpenSettings(defaults: defaults).command, "code $file")
        let editor = SettingsEditor(shortcuts: ShortcutSettings(defaults: defaults), sourceOpenSettings: settings)
        editor.reset(folder: nil)
        XCTAssertEqual(editor.draftSourceOpenCommand, "code $file")
        editor.draftSourceOpenCommand = "other $file"
        editor.reset(folder: nil)
        XCTAssertEqual(editor.draftSourceOpenCommand, "code $file")
        XCTAssertThrowsError(try settings.apply("code $HOME $file"))
        XCTAssertEqual(settings.command, "code $file")
        try settings.apply("  ")
        XCTAssertEqual(SourceOpenSettings(defaults: defaults).command, "")
    }

    func testDefaultAndConfiguredLaunch() throws {
        let (file, executable) = try fixture()
        var defaults: [URL] = []
        var launches: [(URL, [String])] = []
        let opener = SourceOpener(searchPaths: [executable.deletingLastPathComponent().path],
            openDefault: { defaults.append($0); return true }, launch: { launches.append(($0, $1)) })
        try opener.open(file, command: "")
        try opener.open(file, command: " \t ")
        XCTAssertEqual(defaults, [file, file])
        try opener.open(file, command: "editor $file")
        XCTAssertEqual(launches[0].0, executable)
        XCTAssertEqual(launches[0].1, [file.path])
        try opener.open(file, command: "\"\(executable.path)\" --new-window '$file'")
        XCTAssertEqual(launches[1].1, ["--new-window", file.path])
        XCTAssertEqual(defaults.count, 2)
    }

    func testInvalidCommandsDoNotLaunchOrFallBack() throws {
        let (file, executable) = try fixture()
        var defaultCount = 0
        var launchCount = 0
        let opener = SourceOpener(searchPaths: [executable.deletingLastPathComponent().path],
            openDefault: { _ in defaultCount += 1; return true }, launch: { _, _ in launchCount += 1 })
        for command in ["editor", "editor $file $file", "editor $file\neditor $file", "editor $file | cat", "editor $file > out",
                        "editor $file; echo", "editor $HOME $file", "editor $(whoami) $file", "editor `whoami` $file",
                        "editor '$file", "editor x$file", "./editor $file"] {
            XCTAssertThrowsError(try opener.open(file, command: command), command)
        }
        XCTAssertEqual(defaultCount, 0)
        XCTAssertEqual(launchCount, 0)
    }

    func testMissingExecutableAndLaunchFailureDoNotFallBack() throws {
        let (file, executable) = try fixture()
        var defaultCount = 0
        let opener = SourceOpener(searchPaths: [executable.deletingLastPathComponent().path],
            openDefault: { _ in defaultCount += 1; return true },
            launch: { _, _ in throw SourceOpenFailure(message: "テスト起動失敗") })
        XCTAssertThrowsError(try opener.open(file, command: "missing-editor $file")) {
            XCTAssertTrue($0.localizedDescription.contains("見つかりません"))
        }
        XCTAssertThrowsError(try opener.open(file, command: "editor $file")) {
            XCTAssertTrue($0.localizedDescription.contains("テスト起動失敗"))
        }
        XCTAssertEqual(defaultCount, 0)
    }
}
