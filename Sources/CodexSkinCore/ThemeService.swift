import Foundation

public enum ThemeServiceError: LocalizedError, Sendable {
    case themeNotFound(String)
    case invalidConfiguration(String)
    case invalidState(String)
    case backupMissing
    case fileOperation(String)
    case appNotInstalled
    case restartFailed(String)

    public var errorDescription: String? {
        switch self {
        case .themeNotFound(let id): "找不到主题：\(id)"
        case .invalidConfiguration(let message): "Codex 配置无效：\(message)"
        case .invalidState(let message): message
        case .backupMissing: "原始配置备份缺失，已停止恢复以避免数据丢失"
        case .fileOperation(let message): message
        case .appNotInstalled: "未找到 Codex Desktop（com.openai.codex）"
        case .restartFailed(let message): message
        }
    }
}

public struct ThemeServiceStatus: Sendable {
    public let selectedThemeID: String?
    public let configExists: Bool
    public let canRestore: Bool
    public let needsRestart: Bool
    public let app: CodexAppStatus

    public init(
        selectedThemeID: String?,
        configExists: Bool,
        canRestore: Bool,
        needsRestart: Bool,
        app: CodexAppStatus
    ) {
        self.selectedThemeID = selectedThemeID
        self.configExists = configExists
        self.canRestore = canRestore
        self.needsRestart = needsRestart
        self.app = app
    }
}

public struct ThemeChangeResult: Sendable {
    public let changed: Bool
    public let selectedThemeID: String?
    public let needsRestart: Bool

    public init(changed: Bool, selectedThemeID: String?, needsRestart: Bool) {
        self.changed = changed
        self.selectedThemeID = selectedThemeID
        self.needsRestart = needsRestart
    }
}

public actor ThemeService {
    private let store: ConfigurationStore
    private var appService: CodexAppService?

    public init(
        paths: ConfigurationPaths = .live,
        appService: CodexAppService? = nil
    ) {
        self.store = ConfigurationStore(paths: paths)
        self.appService = appService
    }

    public func status() async throws -> ThemeServiceStatus {
        let snapshot = try store.snapshot()
        let app = await resolvedAppService().status()
        return ThemeServiceStatus(
            selectedThemeID: snapshot.state?.selectedThemeID,
            configExists: snapshot.configExists,
            canRestore: snapshot.backupAvailable,
            needsRestart: snapshot.state?.needsRestart ?? false,
            app: app
        )
    }

    @discardableResult
    public func apply(themeID: String) async throws -> ThemeChangeResult {
        guard let theme = ThemeCatalog.theme(id: themeID) else {
            throw ThemeServiceError.themeNotFound(themeID)
        }
        let app = await resolvedAppService().status()
        try store.apply(theme: theme, needsRestart: app.isRunning)
        return ThemeChangeResult(
            changed: true,
            selectedThemeID: theme.id,
            needsRestart: app.isRunning
        )
    }

    @discardableResult
    public func applyAndRestart(themeID: String, timeout: TimeInterval = 10) async throws -> ThemeChangeResult {
        let result = try await apply(themeID: themeID)
        try await restartCodex(timeout: timeout)
        return ThemeChangeResult(changed: result.changed, selectedThemeID: result.selectedThemeID, needsRestart: false)
    }

    @discardableResult
    public func restore() async throws -> ThemeChangeResult {
        let app = await resolvedAppService().status()
        let changed = try store.restore(needsRestart: app.isRunning)
        return ThemeChangeResult(
            changed: changed,
            selectedThemeID: nil,
            needsRestart: changed && app.isRunning
        )
    }

    @discardableResult
    public func restoreAndRestart(timeout: TimeInterval = 10) async throws -> ThemeChangeResult {
        let result = try await restore()
        try await restartCodex(timeout: timeout)
        return ThemeChangeResult(changed: result.changed, selectedThemeID: nil, needsRestart: false)
    }

    public func restartCodex(timeout: TimeInterval = 10) async throws {
        try await resolvedAppService().restart(timeout: timeout)
        try store.markRestarted()
    }

    private func resolvedAppService() async -> CodexAppService {
        if let appService { return appService }
        let service = await MainActor.run { CodexAppService() }
        appService = service
        return service
    }
}
