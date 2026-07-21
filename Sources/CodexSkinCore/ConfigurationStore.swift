import Darwin
import Foundation

public struct ConfigurationPaths: Sendable {
    public let configURL: URL
    public let supportDirectoryURL: URL

    public init(configURL: URL, supportDirectoryURL: URL) {
        self.configURL = configURL
        self.supportDirectoryURL = supportDirectoryURL
    }

    public static var live: ConfigurationPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ConfigurationPaths(
            configURL: home.appendingPathComponent(".codex/config.toml"),
            supportDirectoryURL: home.appendingPathComponent("Library/Application Support/CodexSkinTool")
        )
    }
}

public struct PersistedThemeState: Codable, Equatable, Sendable {
    public let version: Int
    public let originalConfigExisted: Bool
    public var selectedThemeID: String?
    public var needsRestart: Bool
    public var appliedAt: Date?

    public init(
        version: Int = 1,
        originalConfigExisted: Bool,
        selectedThemeID: String?,
        needsRestart: Bool,
        appliedAt: Date?
    ) {
        self.version = version
        self.originalConfigExisted = originalConfigExisted
        self.selectedThemeID = selectedThemeID
        self.needsRestart = needsRestart
        self.appliedAt = appliedAt
    }
}

public struct ConfigurationSnapshot: Sendable {
    public let configExists: Bool
    public let backupAvailable: Bool
    public let state: PersistedThemeState?
}

public struct ConfigurationStore {
    public let paths: ConfigurationPaths
    private let fileManager: FileManager
    private let editor: TOMLDocumentEditor

    public init(
        paths: ConfigurationPaths = .live,
        fileManager: FileManager = .default,
        editor: TOMLDocumentEditor = TOMLDocumentEditor()
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.editor = editor
    }

    public var backupURL: URL {
        paths.supportDirectoryURL.appendingPathComponent("original-config.toml")
    }

    public var stateURL: URL {
        paths.supportDirectoryURL.appendingPathComponent("state.json")
    }

    public func snapshot() throws -> ConfigurationSnapshot {
        let state = try readState()
        return ConfigurationSnapshot(
            configExists: fileManager.fileExists(atPath: paths.configURL.path),
            backupAvailable: state != nil,
            state: state
        )
    }

    public func apply(theme: Theme, needsRestart: Bool) throws {
        do {
            try prepareDirectories()
        } catch {
            throw localizedFileError(error, context: "准备配置目录")
        }
        var state = try readState()
        if state == nil {
            let existingBackup = fileManager.fileExists(atPath: backupURL.path)
            let existed = existingBackup || fileManager.fileExists(atPath: paths.configURL.path)
            if existed && !existingBackup {
                let original = try readData(at: paths.configURL, context: "读取原始 Codex 配置")
                try atomicWrite(original, to: backupURL)
            }
            state = PersistedThemeState(
                originalConfigExisted: existed,
                selectedThemeID: nil,
                needsRestart: false,
                appliedAt: nil
            )
            try writeState(state!)
        }

        let source: Data
        if fileManager.fileExists(atPath: paths.configURL.path) {
            source = try readData(at: paths.configURL, context: "读取 Codex 配置")
        } else {
            source = Data()
        }
        let updated = try editor.applying(theme: theme, to: source)
        try atomicWrite(updated, to: paths.configURL)

        state?.selectedThemeID = theme.id
        state?.needsRestart = needsRestart
        state?.appliedAt = Date()
        try writeState(state!)
    }

    public func restore(needsRestart: Bool) throws -> Bool {
        guard var state = try readState() else { return false }
        if state.originalConfigExisted {
            guard fileManager.fileExists(atPath: backupURL.path) else {
                throw ThemeServiceError.backupMissing
            }
            guard fileManager.fileExists(atPath: paths.configURL.path) else {
                throw ThemeServiceError.invalidState("当前 Codex 配置缺失，已停止恢复以避免覆盖外部变更")
            }
            let current = try readData(at: paths.configURL, context: "读取当前 Codex 配置")
            let original = try readData(at: backupURL, context: "读取原始配置备份")
            let restored = try editor.restoringAppearance(in: current, from: original)
            try atomicWrite(restored, to: paths.configURL)
        } else if fileManager.fileExists(atPath: paths.configURL.path) {
            let current = try readData(at: paths.configURL, context: "读取当前 Codex 配置")
            let restored = try editor.restoringAppearance(in: current, from: Data())
            if editor.isEffectivelyEmpty(restored) {
                do {
                    try fileManager.removeItem(at: paths.configURL)
                } catch {
                    throw localizedFileError(error, context: "删除工具创建的 Codex 配置")
                }
            } else {
                try atomicWrite(restored, to: paths.configURL)
            }
        }

        state.selectedThemeID = nil
        state.needsRestart = needsRestart
        state.appliedAt = nil
        try writeState(state)
        return true
    }

    public func markRestarted() throws {
        guard var state = try readState() else { return }
        state.needsRestart = false
        try writeState(state)
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(
            at: paths.configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: paths.supportDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func readState() throws -> PersistedThemeState? {
        guard fileManager.fileExists(atPath: stateURL.path) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PersistedThemeState.self, from: readData(at: stateURL, context: "读取工具状态"))
        } catch {
            if let serviceError = error as? ThemeServiceError { throw serviceError }
            let value = error as NSError
            throw ThemeServiceError.invalidState("状态文件无法读取（\(value.domain):\(value.code)）")
        }
    }

    private func writeState(_ state: PersistedThemeState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try atomicWrite(encoder.encode(state), to: stateURL)
    }

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            let created = fileManager.createFile(
                atPath: temporary.path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            )
            guard created else {
                throw CocoaError(.fileWriteUnknown)
            }
            guard chmod(temporary.path, S_IRUSR | S_IWUSR) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard rename(temporary.path, destination.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw ThemeServiceError.fileOperation("写入 \(destination.path) 失败：\(error.localizedDescription)")
        }
    }

    private func readData(at url: URL, context: String) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw localizedFileError(error, context: context)
        }
    }

    private func localizedFileError(_ error: Error, context: String) -> ThemeServiceError {
        .fileOperation("\(context)失败（\(errorCode(error))）")
    }

    private func errorCode(_ error: Error) -> String {
        let value = error as NSError
        return "\(value.domain):\(value.code)"
    }
}
