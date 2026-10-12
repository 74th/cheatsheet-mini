import AppKit
import SwiftUI
import Combine
import WebKit
import Carbon.HIToolbox
import Down

struct Entry: Identifiable, Equatable {
    let id: String
    let fileName: String
    let documentTitle: String
    let heading: String
    let markdown: String
    let fileURL: URL
    static func == (lhs: Entry, rhs: Entry) -> Bool { lhs.id == rhs.id && lhs.markdown == rhs.markdown }
}

// Fenced code blocks must not produce spurious headings.
struct MarkdownSplitter {
    static func split(_ contents: String, fileURL: URL) -> [Entry] {
        let lines = contents.components(separatedBy: .newlines)
        var sections: [Entry] = []
        var documentTitle = fileURL.deletingPathExtension().lastPathComponent
        var sectionHeading: String?
        var sectionLines: [String] = []
        var sectionNumber = 0
        var fenceCharacter: Character?
        var fenceWidth = 0
        func flush() {
            guard let title = sectionHeading else { return }
            sections.append(Entry(id: "\(fileURL.path)#\(sectionNumber)",
                                  fileName: fileURL.deletingPathExtension().lastPathComponent,
                                  documentTitle: documentTitle,
                                  heading: title,
                                  markdown: sectionLines.joined(separator: "\n"),
                                  fileURL: fileURL))
        }
        for line in lines {
            let stripped = line.drop(while: { $0 == " " })
            let indentation = line.count - stripped.count
            if indentation <= 3, let marker = stripped.first, marker == "`" || marker == "~" {
                let count = stripped.prefix(while: { $0 == marker }).count
                if let open = fenceCharacter {
                    if marker == open && count >= fenceWidth && stripped.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty {
                        fenceCharacter = nil
                        fenceWidth = 0
                    }
                } else if count >= 3 {
                    fenceCharacter = marker
                    fenceWidth = count
                }
                if sectionHeading != nil { sectionLines.append(line) }
                continue
            }
            if fenceCharacter == nil && indentation <= 3 {
                let candidate = String(stripped)
                if candidate.hasPrefix("# "), sectionHeading == nil {
                    documentTitle = String(candidate.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                }
                if candidate.hasPrefix("## ") && !candidate.hasPrefix("### ") {
                    flush()
                    sectionNumber += 1
                    sectionHeading = String(candidate.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    sectionLines = [line]
                    continue
                }
            }
            if sectionHeading != nil { sectionLines.append(line) }
        }
        flush()
        return sections
    }
}

private func normalize(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
}

private func subsequenceScore(_ needle: String, _ haystack: String) -> Int {
    let characters = Array(haystack)
    var position = 0
    var gapPenalty = 0
    var lastPosition = -1
    for c in needle {
        while position < characters.count && characters[position] != c { position += 1 }
        if position == characters.count { return 0 }
        if lastPosition >= 0 { gapPenalty += max(0, position - lastPosition - 1) }
        lastPosition = position
        position += 1
    }
    return max(1, 35 - gapPenalty)
}

private func textScore(_ rawNeedle: String, _ rawText: String) -> Int {
    let needle = normalize(rawNeedle)
    let text = normalize(rawText)
    guard !needle.isEmpty else { return 1 }
    if needle == text { return 120 }
    if text.hasPrefix(needle) { return 100 }
    if text.contains(needle) { return 85 }
    return subsequenceScore(needle, text)
}

func rank(_ query: String, entries: [Entry]) -> [Entry] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return entries }
    let dotParts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    let hasFileFilter = dotParts.count == 2
    let filePart = hasFileFilter ? dotParts[0] : ""
    let headingPart = hasFileFilter ? dotParts[1] : trimmed
    let tokens = headingPart.split(whereSeparator: \.isWhitespace).map(String.init)
    return entries.compactMap { entry -> (Entry, Int)? in
        var total = 0
        if hasFileFilter {
            let fileScore = textScore(filePart, entry.fileName)
            guard fileScore > 0 else { return nil }
            total += fileScore * 3
        }
        if tokens.isEmpty { return (entry, total) }
        for token in tokens {
            let headingScore = textScore(token, entry.heading)
            let titleScore = textScore(token, entry.documentTitle) / 2
            let filenameScore = hasFileFilter ? 0 : textScore(token, entry.fileName) / 2
            let best = max(headingScore, titleScore, filenameScore)
            guard best > 0 else { return nil }
            total += best
        }
        return (entry, total)
    }
    .sorted { $0.1 == $1.1 ? $0.0.heading < $1.0.heading : $0.1 > $1.1 }
    .map(\.0)
}

@MainActor final class SheetStore: ObservableObject {
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var folderURL: URL?
    @Published private(set) var lastScan: Date?
    @Published private(set) var message = "Markdownフォルダを選択してください"
    private var signatures: [URL: String] = [:]
    private var cached: [URL: [Entry]] = [:]
    private var timer: Timer?
    private var accessActive = false

    private let defaults: UserDefaults
    private let folderAccess: FolderAccess

    init(defaults: UserDefaults = .standard, folderAccess: FolderAccess = FolderAccess(), scheduleTimer: Bool = true) {
        self.defaults = defaults
        self.folderAccess = folderAccess
        if let data = defaults.data(forKey: "folderBookmark") {
            var stale = false
            do {
                let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
                try applyFolder(url, persist: stale)
            } catch { message = "保存したフォルダを復元できません: \(error.localizedDescription)" }
        }
        // Repeating timer only. Panel calls and settings never trigger scanning.
        if scheduleTimer {
            timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.scan() } }
        }
    }

    static func pickFolderURL() -> URL? {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        picker.prompt = "チートシートフォルダを選択"
        return picker.runModal() == .OK ? picker.url : nil
    }

    func chooseFolder() {
        guard let url = Self.pickFolderURL() else { return }
        do { try applyFolder(url) }
        catch {
            let alert = NSAlert()
            alert.messageText = "フォルダを変更できません"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func applyFolder(path: String) throws {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SettingsFailure("フォルダのパスを入力してください。") }
        let expanded = (trimmed as NSString).expandingTildeInPath
        try applyFolder(URL(fileURLWithPath: expanded).standardizedFileURL)
    }

    func applyFolder(_ input: URL, persist: Bool = true) throws {
        let url = URL(fileURLWithPath: input.standardizedFileURL.path, isDirectory: true)
        // The same folder does not invalidate or scan the index.
        guard url != folderURL else { return }
        let started = folderAccess.start(url)
        do {
            try folderAccess.validate(url)
            let bookmark = persist ? try folderAccess.bookmark(url) : nil
            // All fallible preparation is complete before committing.
            if let bookmark { defaults.set(bookmark, forKey: "folderBookmark") }
            if accessActive, let old = folderURL { folderAccess.stop(old) }
            folderURL = url
            accessActive = started
            signatures.removeAll()
            cached.removeAll()
            entries = []
            scan(force: true)
        } catch {
            if started { folderAccess.stop(url) }
            throw error
        }
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        if accessActive, let folderURL { folderAccess.stop(folderURL) }
        accessActive = false
    }

    func scan(force: Bool = false) {
        guard let folderURL else { return }
        let fm = FileManager.default
        // No recursion: contentsOfDirectory only, and only regular .md files.
        guard let files = try? fm.contentsOfDirectory(at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) else {
            message = "フォルダを読み込めません: \(folderURL.path)"
            return
        }
        let markdownFiles = files.filter {
            $0.pathExtension.lowercased() == "md" && ((try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
        }
        var updatedSignatures: [URL: String] = [:]
        var updatedCache: [URL: [Entry]] = [:]
        var failed = 0
        for file in markdownFiles {
            let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let fingerprint = "\(attrs?.contentModificationDate?.timeIntervalSince1970 ?? 0):\(attrs?.fileSize ?? -1)"
            if !force, signatures[file] == fingerprint, let old = cached[file] {
                updatedSignatures[file] = fingerprint
                updatedCache[file] = old
            } else if let text = try? String(contentsOf: file, encoding: .utf8) {
                updatedSignatures[file] = fingerprint
                updatedCache[file] = MarkdownSplitter.split(text, fileURL: file)
            } else {
                failed += 1
            }
        }
        signatures = updatedSignatures
        cached = updatedCache
        entries = updatedCache.keys.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).flatMap { updatedCache[$0] ?? [] }
        lastScan = Date()
        message = "\(markdownFiles.count)ファイル / \(entries.count)見出し" + (failed > 0 ? " (読み込み失敗: \(failed))" : "")
    }
}

// Display relative images as embedded data. WKWebView's HTML string cannot
// reliably load arbitrary file:// URLs, so image bytes are embedded instead.
func embedLocalImages(in html: String, relativeTo fileURL: URL) -> String {
    guard let regex = try? NSRegularExpression(pattern: #"(<img\b[^>]*\bsrc=)(["'])([^"']+)\2"#, options: [.caseInsensitive]) else { return html }
    let ns = html as NSString
    var result = html
    for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed() {
        let original = ns.substring(with: match.range(at: 3))
        guard let decoded = decodeHTMLEntities(original).removingPercentEncoding, !decoded.hasPrefix("/") && !decoded.contains("://") && !decoded.hasPrefix("data:") else { continue }
        let base = fileURL.deletingLastPathComponent().standardizedFileURL
        let imageURL = base.appendingPathComponent(decoded).standardizedFileURL
        guard imageURL.path.hasPrefix(base.path + "/"),
              let image = try? Data(contentsOf: imageURL), image.count < 15_000_000 else { continue }
        let ext = imageURL.pathExtension.lowercased()
        let mime: String
        switch ext {
        case "png": mime = "image/png"
        case "jpg", "jpeg": mime = "image/jpeg"
        case "gif": mime = "image/gif"
        case "webp": mime = "image/webp"
        case "svg": mime = "image/svg+xml"
        default: continue
        }
        let embedded = "data:\(mime);base64,\(image.base64EncodedString())"
        if let range = Range(match.range(at: 3), in: result) { result.replaceSubrange(range, with: embedded) }
    }
    return result
}

struct MarkdownPreview: NSViewRepresentable {
    let entry: Entry?
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard let entry else {
            view.loadHTMLString("<html><body style='font:14px -apple-system;color:#888;padding:20px'>見出しを選択してください</body></html>", baseURL: nil)
            return
        }
        let content = (try? markdownPreviewHTML(entry.markdown, relativeTo: entry.fileURL)) ?? "<pre>表示できませんでした</pre>"
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><style>
        :root { color-scheme: light dark; }
        body { font: 14px/1.65 -apple-system, BlinkMacSystemFont, sans-serif; padding: 14px 24px; overflow-wrap: anywhere; }
        h2 { font-size: 19px; } pre { padding: 13px; overflow-x: auto; border-radius: 8px; background: rgba(130,130,130,.13); }
        code { font-family: ui-monospace, Menlo, monospace; } :not(pre)>code { padding: 2px 4px; background: rgba(130,130,130,.13); }
        img { max-width: 100%; height: auto; } table { border-collapse: collapse; } td, th { border: 1px solid #9996; padding: 5px 10px; }
        a { color: #338bd1; }
        </style></head><body>\(content)</body></html>
        """
        view.loadHTMLString(html, baseURL: nil)
    }
}

struct SearchView: View {
    @ObservedObject var store: SheetStore
    @ObservedObject var shortcuts: ShortcutSettings
    @State private var query = ""
    @State private var selection: String?
    @FocusState private var focused: Bool
    let close: () -> Void
    let openSettings: () -> Void
    var results: [Entry] { Array(rank(query, entries: store.entries).prefix(120)) }
    var selectedEntry: Entry? { results.first(where: { $0.id == selection }) ?? results.first }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("name.title", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19))
                    .focused($focused)
                    .onSubmit { openSource() }
                Text("\(shortcuts.guide) / esc").foregroundStyle(.tertiary).font(.caption)
            }
            .padding(18)
            Divider()
            HSplitView {
                List(results, selection: $selection) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.heading).lineLimit(2)
                        Text(entry.fileName + ".md").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                    .tag(entry.id)
                }
                .listStyle(.sidebar)
                .frame(minWidth: 230, idealWidth: 300)
                MarkdownPreview(entry: selectedEntry)
                    .frame(minWidth: 400)
            }
            Divider()
            HStack(spacing: 12) {
                Text(store.message).foregroundStyle(.secondary)
                Spacer()
                if let scan = store.lastScan { Text("更新: \(scan.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary) }
                Button("再読み込み") { store.scan(force: true) }
                Button("元ファイルを開く") { openSource() }.disabled(selectedEntry == nil)
                Button("設定…", action: openSettings)
            }
            .font(.caption)
            .padding(10)
        }
        .frame(minWidth: 780, minHeight: 480)
        .onAppear { focused = true }
        .onChange(of: query) { _ in selection = results.first?.id }
        .onChange(of: store.entries) { _ in selection = results.first?.id }
        .onReceive(NotificationCenter.default.publisher(for: .cheatSheetShow)) { _ in
            query = ""
            selection = results.first?.id
            focused = true
        }
        .onExitCommand(perform: close)
    }

    private func openSource() {
        guard let entry = selectedEntry else { return }
        NSWorkspace.shared.open(entry.fileURL)
    }
}

extension Notification.Name {
    static let cheatSheetShow = Notification.Name("CheatSheetMini.Show")
}

private func statusBarIcon() -> NSImage? {
    // SwiftPM's command-line build copies imagesets without compiling an asset
    // catalog. Load each resolution into one image at an 18-point logical size.
    // In the packaged app, resources live under Contents/Resources. The generated
    // SwiftPM accessor only searches the app root and the original build folder.
    let resourceBundle = Bundle.main.url(forResource: "CheatSheetMini_CheatSheetMini", withExtension: "bundle")
        .flatMap { Bundle(url: $0) } ?? Bundle.module
    guard let directory = resourceBundle.url(forResource: "StatusBarBirdBook", withExtension: "imageset") else {
        return nil
    }
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size)
    for pixels in [18, 36, 54] {
        let url = directory.appendingPathComponent("bird-book-\(pixels).png")
        guard let data = try? Data(contentsOf: url),
              let representation = NSBitmapImageRep(data: data) else { continue }
        representation.size = size
        image.addRepresentation(representation)
    }
    guard !image.representations.isEmpty else { return nil }
    image.isTemplate = true
    return image
}

@MainActor final class ApplicationController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var hotkeyHandler: EventHandlerRef?
    private var settingsWindow: NSWindow?
    private let shortcuts = ShortcutSettings()
    private lazy var settingsEditor = SettingsEditor(shortcuts: shortcuts)
    private var menuObservation: AnyCancellable?
    private var searchMenuItem: NSMenuItem?
    private let store = SheetStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.title = "CheatSheet Mini"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.center()
        panel.contentView = NSHostingView(rootView: SearchView(
            store: store,
            shortcuts: shortcuts,
            close: { [weak self] in self?.panel.orderOut(nil) },
            openSettings: { [weak self] in self?.openSettings() }
        ))
        self.panel = panel

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = statusBarIcon() {
                button.image = image
                button.imageScaling = .scaleProportionallyDown
            } else {
                button.title = "▤"
            }
            button.toolTip = "CheatSheet Mini"
            button.setAccessibilityLabel("CheatSheet Mini")
        }
        let menu = NSMenu()
        let searchItem = NSMenuItem(title: "検索を開く", action: #selector(togglePanel), keyEquivalent: "")
        searchMenuItem = searchItem
        menu.addItem(searchItem)
        menu.addItem(NSMenuItem(title: "設定…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "今すぐ再読み込み", action: #selector(refreshNow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        installHotkey()
        menuObservation = shortcuts.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateKeyGuide() }
        }
        updateKeyGuide()
        if store.folderURL == nil { store.chooseFolder() }
    }

    private func updateKeyGuide() { searchMenuItem?.title = "検索を開く (\(shortcuts.guide))" }

    @objc func openSettings() {
        panel.orderOut(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "CheatSheet Mini — 設定"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(store: store, shortcuts: shortcuts, editor: settingsEditor))
            window.center()
            settingsWindow = window
        }
        if settingsWindow?.isVisible != true { settingsEditor.reset(folder: store.folderURL) }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow { settingsEditor.reset(folder: store.folderURL) }
    }

    @objc private func refreshNow() { store.scan(force: true) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc func togglePanel() {
        if panel.isVisible { panel.orderOut(nil); return }
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .cheatSheetShow, object: nil)
        // Intentionally no scan on panel calls.
    }

    private func installHotkey() {
        let spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context -> OSStatus in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var keyID = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &keyID)
            guard result == noErr, keyID.signature == hotkeySignature else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<ApplicationController>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                if controller.shortcuts.activeID == keyID.id { controller.togglePanel() }
            }
            return noErr
        }, 1, [spec], opaque, &hotkeyHandler)
        shortcuts.start(handlerError: status == noErr ? nil : "キーのイベント受付を開始できません (\(status))。メニューをご利用ください。")
    }

    func applicationWillTerminate(_ notification: Notification) {
        settingsEditor.stopRecording()
        shortcuts.shutdown()
        store.shutdown()
        if let hotkeyHandler { RemoveEventHandler(hotkeyHandler) }
    }
}

@main struct CheatSheetMiniApplication {
    static func main() {
        let application = NSApplication.shared
        let controller = ApplicationController()
        application.delegate = controller
        application.run()
    }
}
