import XCTest
import AppKit
import Carbon.HIToolbox
@testable import CheatSheetMini

@MainActor final class FakeRegistrar: HotkeyRegistering {
    var fail = false
    var operations: [String] = []
    func register(_ shortcut: Shortcut, id: UInt32) throws -> EventHotKeyRef {
        operations.append("register:\(id)")
        if fail { throw SettingsFailure("登録失敗") }
        return EventHotKeyRef(bitPattern: Int(id))!
    }
    func unregister(_ reference: EventHotKeyRef) { operations.append("unregister:\(Int(bitPattern: reference))") }
}

final class SettingsTests: XCTestCase {
    @MainActor private func isolatedDefaults() -> UserDefaults {
        let name = "CheatSheetMiniTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
    @MainActor func testDefaultsRestorationAndInvalidValues() throws {
        let defaults = isolatedDefaults()
        let registrar = FakeRegistrar()
        let settings = ShortcutSettings(defaults: defaults, registrar: registrar)
        XCTAssertEqual(settings.shortcut, .defaultValue)
        XCTAssertEqual(settings.shortcut.display, "⌘F1")
        settings.start()
        let changed = Shortcut(keyCode: UInt32(kVK_F2), modifiers: UInt32(cmdKey | shiftKey))
        XCTAssertTrue(settings.apply(changed))
        XCTAssertEqual(ShortcutSettings(defaults: defaults, registrar: registrar).shortcut, changed)
        for value in [Shortcut(keyCode: 128, modifiers: UInt32(cmdKey)), Shortcut(keyCode: UInt32(kVK_Command), modifiers: UInt32(cmdKey)),
                      Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0), Shortcut(keyCode: UInt32(kVK_F1), modifiers: UInt32(alphaLock))] {
            XCTAssertFalse(value.isValid)
            XCTAssertFalse(settings.apply(value))
            XCTAssertEqual(settings.shortcut, changed)
        }
        XCTAssertTrue(Shortcut(keyCode: UInt32(kVK_F20), modifiers: 0).isValid)
        defaults.set(Data("broken".utf8), forKey: ShortcutSettings.storageKey)
        let broken = ShortcutSettings(defaults: defaults, registrar: registrar)
        XCTAssertEqual(broken.shortcut, .defaultValue)
        XCTAssertNotNil(broken.loadWarning)
        defaults.set(try JSONEncoder().encode(Shortcut(keyCode: 200, modifiers: 0)), forKey: ShortcutSettings.storageKey)
        XCTAssertNotNil(ShortcutSettings(defaults: defaults, registrar: registrar).loadWarning)
        defaults.set("wrong type", forKey: ShortcutSettings.storageKey)
        XCTAssertNotNil(ShortcutSettings(defaults: defaults, registrar: registrar).loadWarning)
        settings.shutdown()
    }
    @MainActor func testTransactionalRegistrationAndRetry() {
        let defaults = isolatedDefaults()
        let registrar = FakeRegistrar()
        let settings = ShortcutSettings(defaults: defaults, registrar: registrar)
        settings.start()
        XCTAssertTrue(settings.registered)
        XCTAssertTrue(settings.apply(.defaultValue))
        XCTAssertEqual(registrar.operations, ["register:1"])
        let saved = defaults.data(forKey: ShortcutSettings.storageKey)
        let changed = Shortcut(keyCode: UInt32(kVK_F2), modifiers: UInt32(cmdKey | shiftKey))
        registrar.fail = true
        XCTAssertFalse(settings.apply(changed))
        XCTAssertEqual(settings.shortcut, .defaultValue)
        XCTAssertEqual(settings.activeID, 1)
        XCTAssertEqual(defaults.data(forKey: ShortcutSettings.storageKey), saved)
        XCTAssertEqual(registrar.operations, ["register:1", "register:2"])
        XCTAssertEqual(settings.guide, "⌘F1")
        registrar.fail = false
        XCTAssertTrue(settings.apply(changed))
        XCTAssertEqual(Array(registrar.operations.suffix(2)), ["register:3", "unregister:1"])
        XCTAssertEqual(settings.guide, "⇧⌘F2")
        settings.unregister()
        XCTAssertTrue(settings.apply(changed))
        XCTAssertEqual(settings.activeID, 4)
        settings.shutdown()
    }
    @MainActor func testStartupFailureAndRecordingRestoration() {
        let registrar = FakeRegistrar()
        registrar.fail = true
        let settings = ShortcutSettings(defaults: isolatedDefaults(), registrar: registrar)
        settings.start()
        XCTAssertFalse(settings.registered)
        XCTAssertTrue(settings.guide.contains("利用不可"))
        XCTAssertNotNil(settings.error)
        registrar.fail = false
        XCTAssertTrue(settings.apply(Shortcut(keyCode: UInt32(kVK_F2), modifiers: UInt32(cmdKey))))
        let old = settings.shortcut
        settings.beginRecording()
        XCTAssertNil(settings.activeID)
        XCTAssertFalse(settings.registered)
        XCTAssertFalse(settings.apply(.defaultValue))
        settings.endRecording()
        XCTAssertTrue(settings.registered)
        XCTAssertEqual(settings.shortcut, old)
        settings.beginRecording()
        registrar.fail = true
        settings.endRecording()
        XCTAssertFalse(settings.registered)
        XCTAssertNotNil(settings.error)
        registrar.fail = false
        XCTAssertTrue(settings.apply(old))
        settings.shutdown()
    }
    @MainActor func testEditorDiscardsDraftAndRestoresRecording() {
        let settings = ShortcutSettings(defaults: isolatedDefaults(), registrar: FakeRegistrar())
        settings.start()
        let editor = SettingsEditor(shortcuts: settings, sourceOpenSettings: SourceOpenSettings(defaults: isolatedDefaults()))
        editor.folderPath = "/unapplied"
        editor.draftShortcut = Shortcut(keyCode: UInt32(kVK_F2), modifiers: 0)
        settings.beginRecording()
        editor.reset(folder: nil)
        XCTAssertEqual(editor.folderPath, "")
        XCTAssertEqual(editor.draftShortcut, .defaultValue)
        XCTAssertFalse(settings.recording)
        XCTAssertTrue(settings.registered)
        settings.shutdown()
    }
    @MainActor func testRecordingAcceptsCurrentKeyRejectsInvalidAndDoesNotApply() {
        let defaults = isolatedDefaults()
        let settings = ShortcutSettings(defaults: defaults, registrar: FakeRegistrar())
        settings.start()
        let editor = SettingsEditor(shortcuts: settings, sourceOpenSettings: SourceOpenSettings(defaults: isolatedDefaults()))
        func key(_ code: Int, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                             isARepeat: false, keyCode: UInt16(code))!
        }
        settings.beginRecording()
        XCTAssertNil(editor.capture(key(kVK_ANSI_A)))
        XCTAssertNotNil(editor.inputError)
        XCTAssertTrue(settings.recording)
        XCTAssertNil(editor.capture(key(kVK_Command, flags: .command)))
        XCTAssertTrue(settings.recording)
        XCTAssertNil(editor.capture(key(kVK_F1, flags: [.command, .function])))
        XCTAssertFalse(settings.recording)
        XCTAssertTrue(settings.registered)
        XCTAssertEqual(editor.draftShortcut, .defaultValue)
        settings.beginRecording()
        _ = editor.capture(key(kVK_F2, flags: [.command, .shift]))
        XCTAssertEqual(editor.draftShortcut.display, "⇧⌘F2")
        XCTAssertEqual(settings.shortcut, .defaultValue)
        XCTAssertNil(defaults.data(forKey: ShortcutSettings.storageKey))
        settings.beginRecording()
        _ = editor.capture(key(kVK_Escape))
        XCTAssertFalse(settings.recording)
        XCTAssertTrue(settings.registered)
        settings.shutdown()
    }
    @MainActor func testFolderCommitFailuresSwitchAndLegacyRestore() throws {
        let defaults = isolatedDefaults()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first", isDirectory: true)
        let second = root.appendingPathComponent("second", isDirectory: true)
        for folder in [first, second] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try "## codex\nold".write(to: first.appendingPathComponent("sbx.md"), atomically: true, encoding: .utf8)
        try "## other\nnew".write(to: second.appendingPathComponent("new.md"), atomically: true, encoding: .utf8)
        let nested = second.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "## excluded".write(to: nested.appendingPathComponent("nested.md"), atomically: true, encoding: .utf8)
        var failBookmark = false
        var failAccess = false
        var stops: [URL] = []
        let access = FolderAccess(start: { _ in true }, stop: { stops.append($0) }, bookmark: {
            if failBookmark { throw SettingsFailure("bookmark失敗") }
            return try $0.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        }, validate: {
            if failAccess { throw SettingsFailure("アクセス失敗") }
            try FolderAccess().validate($0)
        })
        let store = SheetStore(defaults: defaults, folderAccess: access, scheduleTimer: false)
        try store.applyFolder(path: "  \(first.path)/../first  \n")
        XCTAssertEqual(store.folderURL, first)
        XCTAssertEqual(rank("sbx.codex", entries: store.entries).count, 1)
        let entries = store.entries
        let bookmark = defaults.data(forKey: "folderBookmark")
        let scan = store.lastScan
        for path in ["", "   ", root.appendingPathComponent("missing").path, first.appendingPathComponent("sbx.md").path] {
            XCTAssertThrowsError(try store.applyFolder(path: path))
            XCTAssertEqual(store.entries, entries)
            XCTAssertEqual(store.folderURL, first)
            XCTAssertEqual(defaults.data(forKey: "folderBookmark"), bookmark)
        }
        failBookmark = true
        XCTAssertThrowsError(try store.applyFolder(second))
        failBookmark = false
        failAccess = true
        XCTAssertThrowsError(try store.applyFolder(second))
        failAccess = false
        XCTAssertEqual(store.entries, entries)
        XCTAssertEqual(store.lastScan, scan)
        XCTAssertEqual(defaults.data(forKey: "folderBookmark"), bookmark)
        XCTAssertTrue(stops.contains(second))
        try store.applyFolder(first)
        XCTAssertEqual(store.lastScan, scan)
        // Existing bookmark key/format is the sole restoration source.
        let restored = SheetStore(defaults: defaults, scheduleTimer: false)
        XCTAssertEqual(restored.folderURL, first)
        XCTAssertEqual(restored.entries, entries)
        restored.shutdown()
        try store.applyFolder(second)
        XCTAssertEqual(store.entries.map(\.heading), ["other"])
        XCTAssertEqual(rank("", entries: store.entries).count, 1)
        XCTAssertTrue(rank("sbx.codex", entries: store.entries).isEmpty)
        XCTAssertTrue(stops.contains(first))
        store.shutdown()
    }
    @MainActor func testNewFolderImageAndTwoHundredFileSearch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("<svg/>".utf8).write(to: root.appendingPathComponent("image.svg"))
        for index in 0..<200 {
            try "## codex \(index)\n![test](image.svg)".write(to: root.appendingPathComponent("sbx\(index).md"), atomically: true, encoding: .utf8)
        }
        let store = SheetStore(defaults: isolatedDefaults(), scheduleTimer: false)
        try store.applyFolder(root)
        XCTAssertEqual(store.entries.count, 200)
        XCTAssertEqual(rank("", entries: store.entries).count, 200)
        XCTAssertEqual(rank("sbx.codex", entries: store.entries).count, 200)
        let html = embedLocalImages(in: "<img src=\"image.svg\">", relativeTo: store.entries[0].fileURL)
        XCTAssertTrue(html.contains("data:image/svg+xml;base64,"))
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 { _ = rank("sbx.codex", entries: store.entries) }
        print("200-file rank average: \((CFAbsoluteTimeGetCurrent() - start) * 10) ms; excludes UI and preview")
        store.shutdown()
    }
}
