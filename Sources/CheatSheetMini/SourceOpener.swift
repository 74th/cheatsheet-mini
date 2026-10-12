import AppKit
import Foundation

struct SourceOpenFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct SourceOpener {
    let searchPaths: [String]
    let openDefault: (URL) -> Bool
    let launch: (URL, [String]) throws -> Void

    init(
        searchPaths: [String] = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init) + ["/usr/local/bin", "/opt/homebrew/bin"],
        openDefault: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        launch: @escaping (URL, [String]) throws -> Void = { executable, arguments in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            try process.run()
        }
    ) {
        self.searchPaths = searchPaths
        self.openDefault = openDefault
        self.launch = launch
    }

    func open(_ fileURL: URL, command: String) throws {
        let file = fileURL.standardizedFileURL.path
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            guard openDefault(fileURL.standardizedFileURL) else {
                throw SourceOpenFailure(message: "macOSの既定アプリで元ファイルを開けませんでした。")
            }
            return
        }
        let parts = try Self.parse(command.trimmingCharacters(in: .whitespacesAndNewlines))
        let executable = try resolveExecutable(parts[0])
        let arguments = parts.dropFirst().map { $0 == "$file" ? file : $0 }
        do {
            try launch(executable, arguments)
        } catch {
            throw SourceOpenFailure(message: "起動コマンド「\(parts[0])」を開始できません: \(error.localizedDescription)")
        }
    }

    static func parse(_ command: String) throws -> [String] {
        guard !command.contains("\n"), !command.contains("\r") else {
            throw SourceOpenFailure(message: "起動コマンドは1行で指定してください。")
        }
        var words: [String] = []
        var word = ""
        var quote: Character?
        var started = false
        for character in command {
            if let currentQuote = quote {
                if character == currentQuote { quote = nil }
                else { word.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
                started = true
            } else if character.isWhitespace {
                if started { words.append(word); word = ""; started = false }
            } else {
                word.append(character)
                started = true
            }
        }
        guard quote == nil else { throw SourceOpenFailure(message: "起動コマンドの引用符が閉じていません。") }
        if started { words.append(word) }
        guard let executable = words.first, !executable.isEmpty else {
            throw SourceOpenFailure(message: "起動コマンドが空です。")
        }
        guard words.dropFirst().filter({ $0 == "$file" }).count == 1 else {
            throw SourceOpenFailure(message: "起動コマンドには引数「$file」を1回だけ指定してください。")
        }
        let forbidden = CharacterSet(charactersIn: "|&;<>`\\()")
        guard words.allSatisfy({ $0.rangeOfCharacter(from: forbidden) == nil && ($0 == "$file" || !$0.contains("$")) }) else {
            throw SourceOpenFailure(message: "パイプ・リダイレクト・変数展開などのシェル構文は使用できません。")
        }
        return words
    }

    private func resolveExecutable(_ command: String) throws -> URL {
        let candidates: [String]
        if command.hasPrefix("/") { candidates = [command] }
        else if !command.contains("/") { candidates = searchPaths.map { ($0 as NSString).appendingPathComponent(command) } }
        else { candidates = [] }
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        throw SourceOpenFailure(message: "実行ファイル「\(command)」が見つかりません。PATHを確認するか、設定に絶対パスを指定してください。")
    }
}
