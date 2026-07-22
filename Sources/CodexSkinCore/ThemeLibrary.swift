import Darwin
import Foundation

public enum ThemeLibraryKind: String, Codable, Sendable {
    case builtIn
    case custom
}

public struct ThemeLibraryItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: ThemeLibraryKind
    public let theme: Theme
    public let customDraft: CustomThemeDraft?

    public init(id: String, kind: ThemeLibraryKind, theme: Theme, customDraft: CustomThemeDraft? = nil) {
        self.id = id
        self.kind = kind
        self.theme = theme
        self.customDraft = customDraft
    }
}

public struct SavedCustomTheme: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var draft: CustomThemeDraft

    public init(id: String = "user-\(UUID().uuidString)", draft: CustomThemeDraft) {
        self.id = id
        self.draft = draft
    }

    public var theme: Theme { draft.theme(id: id) }
}

public struct ThemeLibraryState: Codable, Equatable, Sendable {
    public var version: Int
    public var hiddenBuiltInIDs: Set<String>
    public var customThemes: [SavedCustomTheme]

    public init(version: Int = 1, hiddenBuiltInIDs: Set<String> = [], customThemes: [SavedCustomTheme] = []) {
        self.version = version
        self.hiddenBuiltInIDs = hiddenBuiltInIDs
        self.customThemes = customThemes
    }
}

public struct ThemeLibraryStore {
    public let supportDirectoryURL: URL
    private let fileManager: FileManager

    public init(
        supportDirectoryURL: URL = ConfigurationPaths.live.supportDirectoryURL,
        fileManager: FileManager = .default
    ) {
        self.supportDirectoryURL = supportDirectoryURL
        self.fileManager = fileManager
    }

    public var libraryURL: URL { supportDirectoryURL.appendingPathComponent("theme-library.json") }

    public func loadState() throws -> ThemeLibraryState {
        guard fileManager.fileExists(atPath: libraryURL.path) else { return ThemeLibraryState() }
        do {
            let state = try JSONDecoder().decode(ThemeLibraryState.self, from: Data(contentsOf: libraryURL))
            let backgroundStore = CustomThemeStore(
                supportDirectoryURL: supportDirectoryURL,
                fileManager: fileManager
            )
            let backgroundNames = state.customThemes.compactMap(\.draft.backgroundImageName)
            guard state.version == 1,
                  Set(state.customThemes.map(\.id)).count == state.customThemes.count,
                  state.customThemes.allSatisfy({ $0.id.hasPrefix("user-") }),
                  Set(backgroundNames).count == backgroundNames.count,
                  backgroundNames.allSatisfy({ backgroundStore.backgroundURL(named: $0) != nil }) else {
                throw ThemeServiceError.invalidState("主题资料库格式无效")
            }
            return state
        } catch let error as ThemeServiceError {
            throw error
        } catch {
            throw ThemeServiceError.invalidState("主题资料库无法读取")
        }
    }

    public func items() throws -> [ThemeLibraryItem] {
        let state = try loadState()
        let builtIns = ThemeCatalog.builtIn
            .filter { !state.hiddenBuiltInIDs.contains($0.id) }
            .map { ThemeLibraryItem(id: $0.id, kind: .builtIn, theme: $0) }
        let customs = state.customThemes.map {
            ThemeLibraryItem(id: $0.id, kind: .custom, theme: $0.theme, customDraft: $0.draft)
        }
        return builtIns + customs
    }

    public func saveCustom(_ source: CustomThemeDraft, replacing id: String? = nil) throws -> SavedCustomTheme {
        var state = try loadState()
        let backgroundStore = CustomThemeStore(supportDirectoryURL: supportDirectoryURL, fileManager: fileManager)
        var draft = source
        draft.backgroundImageName = try backgroundStore.copyBackground(named: source.backgroundImageName)
        let saved = SavedCustomTheme(id: id ?? "user-\(UUID().uuidString)", draft: draft)
        guard saved.id.hasPrefix("user-") else { throw ThemeServiceError.invalidState("自定义主题 ID 无效") }

        if let index = state.customThemes.firstIndex(where: { $0.id == saved.id }) {
            let previous = state.customThemes[index]
            state.customThemes[index] = saved
            do {
                try write(state)
                try? backgroundStore.removeBackground(named: previous.draft.backgroundImageName)
            } catch {
                try? backgroundStore.removeBackground(named: draft.backgroundImageName)
                throw error
            }
        } else {
            state.customThemes.append(saved)
            do {
                try write(state)
            } catch {
                try? backgroundStore.removeBackground(named: draft.backgroundImageName)
                throw error
            }
        }
        return saved
    }

    public func delete(itemID: String) throws {
        var state = try loadState()
        if ThemeCatalog.theme(id: itemID) != nil {
            state.hiddenBuiltInIDs.insert(itemID)
            try write(state)
            return
        }
        guard let index = state.customThemes.firstIndex(where: { $0.id == itemID }) else { return }
        let removed = state.customThemes.remove(at: index)
        try write(state)
        try? CustomThemeStore(supportDirectoryURL: supportDirectoryURL, fileManager: fileManager)
            .removeBackground(named: removed.draft.backgroundImageName)
    }

    public func renameCustom(itemID: String, name: String) throws -> SavedCustomTheme {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw ThemeServiceError.invalidState("主题名称不能为空")
        }
        guard normalizedName.count <= 40 else {
            throw ThemeServiceError.invalidState("主题名称不能超过 40 个字符")
        }
        guard normalizedName.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw ThemeServiceError.invalidState("主题名称不能包含控制字符")
        }
        var state = try loadState()
        guard let index = state.customThemes.firstIndex(where: { $0.id == itemID }) else {
            throw ThemeServiceError.invalidState("只能重命名已保存的自定义主题")
        }
        state.customThemes[index].draft.name = normalizedName
        try write(state)
        return state.customThemes[index]
    }

    public func restoreBuiltIns() throws {
        var state = try loadState()
        guard !state.hiddenBuiltInIDs.isEmpty else { return }
        state.hiddenBuiltInIDs.removeAll()
        try write(state)
    }

    private func write(_ state: ThemeLibraryState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try fileManager.createDirectory(at: supportDirectoryURL, withIntermediateDirectories: true)
        let temporary = supportDirectoryURL.appendingPathComponent(".theme-library.\(UUID().uuidString).tmp")
        do {
            guard fileManager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]),
                  chmod(temporary.path, S_IRUSR | S_IWUSR) == 0,
                  rename(temporary.path, libraryURL.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw ThemeServiceError.fileOperation("写入主题资料库失败：\(error.localizedDescription)")
        }
    }
}
