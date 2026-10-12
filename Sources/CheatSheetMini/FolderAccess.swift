import Foundation

// Injectable preparation allows testing denied access and bookmark failures.
struct FolderAccess {
    var start: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() }
    var stop: (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
    var bookmark: (URL) throws -> Data = {
        try $0.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    var validate: (URL) throws -> Void = { url in
        var directory: ObjCBool = false
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
            throw SettingsFailure("存在するフォルダを指定してください。個別ファイルは指定できません。")
        }
        // A false startAccessing result is normal for this non-sandboxed app;
        // actual readability and enumeration determine whether access works.
        guard fm.isReadableFile(atPath: url.path) else { throw SettingsFailure("フォルダの読み取り権限がありません。") }
        _ = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }
}
