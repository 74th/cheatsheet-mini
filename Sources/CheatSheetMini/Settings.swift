import AppKit
import SwiftUI
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    static let allowedModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
    static let defaultValue = Shortcut(keyCode: UInt32(kVK_F1), modifiers: UInt32(cmdKey))
    static let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                               kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
    var isValid: Bool {
        keyCode <= 127 && ![kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option, kVK_RightOption,
                           kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function].contains(Int(keyCode))
            && modifiers & ~Self.allowedModifiers == 0
            && (modifiers != 0 || Self.functionKeys.contains(Int(keyCode)))
    }
    init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        var flags: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.command, cmdKey), (.option, optionKey), (.control, controlKey), (.shift, shiftKey)] {
            if event.modifierFlags.contains(flag) { flags |= UInt32(carbon) }
        }
        modifiers = flags
    }
    var display: String {
        var prefix = ""
        for (flag, symbol) in [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")] {
            if modifiers & UInt32(flag) != 0 { prefix += symbol }
        }
        if let index = Self.functionKeys.firstIndex(of: Int(keyCode)) { return prefix + "F\(index + 1)" }
        let special = [kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
                       kVK_Escape: "Esc", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
                       kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down"]
        if let name = special[Int(keyCode)] { return prefix + name }
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        if let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
            var dead: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 8)
            if UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                              OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, characters.count, &length, &characters) == noErr, length > 0 {
                return prefix + String(utf16CodeUnits: characters, count: length).uppercased()
            }
        }
        return prefix + "Key \(keyCode)"
    }
}

let hotkeySignature: OSType = 0x43534D49 // CSMI

@MainActor protocol HotkeyRegistering {
    func register(_ shortcut: Shortcut, id: UInt32) throws -> EventHotKeyRef
    func unregister(_ reference: EventHotKeyRef)
}

struct SettingsFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

@MainActor final class CarbonHotkeyRegistrar: HotkeyRegistering {
    func register(_ shortcut: Shortcut, id: UInt32) throws -> EventHotKeyRef {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: hotkeySignature, id: id),
                                         GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { throw SettingsFailure("キーを登録できません (\(status))。別のキーを試してください。") }
        return reference
    }
    func unregister(_ reference: EventHotKeyRef) { UnregisterEventHotKey(reference) }
}

@MainActor final class ShortcutSettings: ObservableObject {
    @Published private(set) var shortcut: Shortcut
    @Published private(set) var registered = false
    @Published private(set) var error: String?
    @Published private(set) var loadWarning: String?
    @Published private(set) var recording = false
    // Layout changes refresh all key labels without reading defaults or scanning.
    @Published private var layoutRevision = 0
    private let defaults: UserDefaults
    private let registrar: HotkeyRegistering
    private var reference: EventHotKeyRef?
    private(set) var activeID: UInt32?
    private var nextID: UInt32 = 1
    private var handlerReady = false
    private var layoutObserver: NSObjectProtocol?
    static let storageKey = "searchShortcut"
    var guide: String { shortcut.display + (registered ? "" : recording ? "（記録中）" : "（利用不可）") }

    init(defaults: UserDefaults = .standard, registrar: HotkeyRegistering? = nil) {
        self.defaults = defaults
        self.registrar = registrar ?? CarbonHotkeyRegistrar()
        if let value = defaults.object(forKey: Self.storageKey) {
            if let data = value as? Data, let saved = try? JSONDecoder().decode(Shortcut.self, from: data), saved.isValid {
                shortcut = saved
            } else {
                shortcut = .defaultValue
                loadWarning = "保存されたキー設定が壊れているため、既定の⌘F1を使用します。適用して保存し直してください。"
            }
        } else { shortcut = .defaultValue }
        layoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.layoutRevision += 1 } }
    }
    func start(handlerError: String? = nil) {
        handlerReady = handlerError == nil
        if let handlerError { error = handlerError; return }
        _ = apply(shortcut, persist: false)
    }
    @discardableResult func apply(_ value: Shortcut, persist: Bool = true) -> Bool {
        guard value.isValid else { error = "修飾キーだけは使えません。通常のキーには⌘・⌥・⌃・⇧を付けてください。"; return false }
        guard handlerReady, !recording else { error = "キーの受付を開始できません。記録を終了するかアプリを再起動してください。"; return false }
        do {
            // Prepare persistence before modifying any registrations.
            let data = try JSONEncoder().encode(value)
            if value != shortcut || reference == nil {
                let id = nextID
                nextID &+= 1
                let newReference = try registrar.register(value, id: id)
                let old = reference
                reference = newReference
                activeID = id
                if let old { registrar.unregister(old) }
            }
            shortcut = value
            registered = true
            error = nil
            if persist { defaults.set(data, forKey: Self.storageKey); loadWarning = nil }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func beginRecording() {
        guard !recording else { return }
        recording = true
        unregister()
    }
    func endRecording() {
        guard recording else { return }
        recording = false
        _ = apply(shortcut, persist: false)
    }
    func unregister() {
        activeID = nil
        if let reference { registrar.unregister(reference) }
        reference = nil
        registered = false
    }
    func shutdown() {
        recording = false
        unregister()
        if let layoutObserver { DistributedNotificationCenter.default().removeObserver(layoutObserver) }
        layoutObserver = nil
    }
}

@MainActor final class SettingsEditor: ObservableObject {
    @Published var folderPath = ""
    @Published var draftShortcut = Shortcut.defaultValue
    @Published var folderError: String?
    @Published var inputError: String?
    private var eventMonitor: Any?
    let shortcuts: ShortcutSettings
    init(shortcuts: ShortcutSettings) { self.shortcuts = shortcuts }
    func reset(folder: URL?) {
        stopRecording()
        folderPath = folder?.path ?? ""
        draftShortcut = shortcuts.shortcut
        folderError = nil
        inputError = nil
    }
    func record() {
        shortcuts.beginRecording()
        inputError = nil
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.capture(event)
        }
    }
    func capture(_ event: NSEvent) -> NSEvent? {
        if event.type == .flagsChanged { inputError = "修飾キーに加えてキーを押してください。"; return event }
        if event.keyCode == kVK_Escape, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            stopRecording(); return nil
        }
        let value = Shortcut(event: event)
        guard value.isValid else { inputError = "修飾なしはF1〜F20のみです。"; return nil }
        draftShortcut = value
        inputError = nil
        stopRecording()
        return nil
    }
    func stopRecording() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        shortcuts.endRecording()
    }
}

struct SettingsView: View {
    @ObservedObject var store: SheetStore
    @ObservedObject var shortcuts: ShortcutSettings
    @ObservedObject var editor: SettingsEditor
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("設定").font(.title2)
            Text("検索対象フォルダ").font(.headline)
            Text(store.folderURL?.path ?? "未設定").font(.caption).textSelection(.enabled)
            HStack {
                TextField("フォルダのパス", text: $editor.folderPath)
                Button("選択…") {
                    if let url = SheetStore.pickFolderURL() { editor.folderPath = url.path }
                }
                Button("フォルダを適用") {
                    do { try store.applyFolder(path: editor.folderPath); editor.folderPath = store.folderURL?.path ?? ""; editor.folderError = nil }
                    catch { editor.folderError = error.localizedDescription }
                }
            }
            if let error = editor.folderError { Text(error).foregroundStyle(.red) }
            Divider()
            Text("検索パネルのショートカット").font(.headline)
            Text("現在: \(shortcuts.guide)")
            HStack {
                Button(shortcuts.recording ? "キーを押してください…" : editor.draftShortcut.display + " を記録…") { editor.record() }
                    .disabled(shortcuts.recording)
                if shortcuts.recording { Button("キャンセル") { editor.stopRecording() } }
                Button("キーを適用") { _ = shortcuts.apply(editor.draftShortcut) }.disabled(shortcuts.recording)
            }
            if let error = editor.inputError { Text(error).foregroundStyle(.red) }
            if let error = shortcuts.error { Text(error).foregroundStyle(.red) }
            if let warning = shortcuts.loadWarning { Text(warning).foregroundStyle(.orange) }
            Text("修飾なしはF1〜F20。Escで記録をキャンセルします。機種やシステム設定によりFnも必要です。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
        .padding(24)
        .frame(width: 680)
        .onChange(of: store.folderURL) { url in editor.folderPath = url?.path ?? ""; editor.folderError = nil }
    }
}
