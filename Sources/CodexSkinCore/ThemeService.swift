import Foundation

public enum ThemeServiceError: LocalizedError, Sendable {
    case themeNotFound(String)
    case invalidConfiguration(String)
    case invalidState(String)
    case backupMissing
    case fileOperation(String)
    case appNotInstalled
    case restartFailed(String)
    case invalidBackground(String)
    case backgroundSession(String)

    public var errorDescription: String? {
        switch self {
        case .themeNotFound(let id): "找不到主题：\(id)"
        case .invalidConfiguration(let message): "Codex 配置无效：\(message)"
        case .invalidState(let message): message
        case .backupMissing: "原始配置备份缺失，已停止恢复以避免数据丢失"
        case .fileOperation(let message): message
        case .appNotInstalled: "未找到 Codex Desktop（com.openai.codex）"
        case .restartFailed(let message): message
        case .invalidBackground(let message): "背景图片无效：\(message)"
        case .backgroundSession(let message): "图片皮肤启动失败：\(message)"
        }
    }
}

public struct ThemeServiceStatus: Sendable {
    public let selectedThemeID: String?
    public let configExists: Bool
    public let canRestore: Bool
    public let needsRestart: Bool
    public let app: CodexAppStatus
    public let backgroundSkin: BackgroundSkinStatus

    public init(
        selectedThemeID: String?,
        configExists: Bool,
        canRestore: Bool,
        needsRestart: Bool,
        app: CodexAppStatus,
        backgroundSkin: BackgroundSkinStatus = .inactive
    ) {
        self.selectedThemeID = selectedThemeID
        self.configExists = configExists
        self.canRestore = canRestore
        self.needsRestart = needsRestart
        self.app = app
        self.backgroundSkin = backgroundSkin
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
    private let customStore: CustomThemeStore
    private let backgroundSession: BackgroundSkinSession
    private var appService: CodexAppService?

    public init(
        paths: ConfigurationPaths = .live,
        appService: CodexAppService? = nil
    ) {
        self.store = ConfigurationStore(paths: paths)
        self.customStore = CustomThemeStore(supportDirectoryURL: paths.supportDirectoryURL)
        self.backgroundSession = BackgroundSkinSession(supportDirectoryURL: paths.supportDirectoryURL)
        self.appService = appService
    }

    public func status() async throws -> ThemeServiceStatus {
        let snapshot = try store.snapshot()
        let service = await resolvedAppService()
        let backgroundSkin = try await backgroundSession.reconcile(appService: service)
        let app = await service.status()
        return ThemeServiceStatus(
            selectedThemeID: snapshot.state?.selectedThemeID,
            configExists: snapshot.configExists,
            canRestore: snapshot.backupAvailable,
            needsRestart: snapshot.state?.needsRestart ?? false,
            app: app,
            backgroundSkin: backgroundSkin
        )
    }

    public func customTheme() throws -> CustomThemeDraft {
        try customStore.load()
    }

    public func saveCustomTheme(_ draft: CustomThemeDraft) throws {
        try customStore.save(draft)
    }

    public func importBackground(from url: URL, into draft: CustomThemeDraft) throws -> CustomThemeDraft {
        let previousName = draft.backgroundImageName
        var updated = draft
        let importedName = try customStore.importBackground(from: url)
        updated.backgroundImageName = importedName
        do {
            try customStore.save(updated)
        } catch {
            try? customStore.removeBackground(named: importedName)
            throw error
        }
        if previousName != importedName { try? customStore.removeBackground(named: previousName) }
        return updated
    }

    public func removeBackground(from draft: CustomThemeDraft) throws -> CustomThemeDraft {
        var updated = draft
        updated.backgroundImageName = nil
        try customStore.save(updated)
        try customStore.removeBackground(named: draft.backgroundImageName)
        return updated
    }

    public func backgroundURL(for draft: CustomThemeDraft) -> URL? {
        customStore.backgroundURL(named: draft.backgroundImageName)
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
        let service = await resolvedAppService()
        _ = try await backgroundSession.recoverAndStop(appService: service)
        do {
            let result = try await apply(themeID: themeID)
            try await restartCodex(timeout: timeout)
            return ThemeChangeResult(changed: result.changed, selectedThemeID: result.selectedThemeID, needsRestart: false)
        } catch {
            try? await service.terminate(timeout: 5)
            try? await MainActor.run { try service.open() }
            throw error
        }
    }

    @discardableResult
    public func applyCustomAndRestart(_ draft: CustomThemeDraft) async throws -> ThemeChangeResult {
        let checkpoint = try store.checkpoint()
        try customStore.save(draft)
        do {
            let app = await resolvedAppService().status()
            try store.apply(theme: draft.theme, needsRestart: app.isRunning)
            if let skin = draft.skinSettings {
                try await backgroundSession.start(
                    settings: skin,
                    theme: draft.theme,
                    appService: await resolvedAppService()
                )
                try store.markRestarted()
            } else {
                _ = try await backgroundSession.recoverAndStop(appService: await resolvedAppService())
                try await restartCodex()
            }
        } catch {
            do {
                try store.rollback(to: checkpoint)
            } catch {
                throw ThemeServiceError.invalidState("图片皮肤失败，且无法回滚本次外观变更：\(error.localizedDescription)")
            }
            let service = await resolvedAppService()
            try? await MainActor.run { try service.open() }
            throw error
        }
        return ThemeChangeResult(changed: true, selectedThemeID: draft.theme.id, needsRestart: false)
    }

    @discardableResult
    public func restore() async throws -> ThemeChangeResult {
        let service = await resolvedAppService()
        _ = try await backgroundSession.recoverAndStop(appService: service)
        let app = await service.status()
        let changed = try store.restore(needsRestart: app.isRunning)
        return ThemeChangeResult(
            changed: changed,
            selectedThemeID: nil,
            needsRestart: changed && app.isRunning
        )
    }

    @discardableResult
    public func restoreAndRestart(timeout: TimeInterval = 10) async throws -> ThemeChangeResult {
        do {
            let result = try await restore()
            try await restartCodex(timeout: timeout)
            return ThemeChangeResult(changed: result.changed, selectedThemeID: nil, needsRestart: false)
        } catch {
            let service = await resolvedAppService()
            try? await service.terminate(timeout: 5)
            try? await MainActor.run { try service.open() }
            throw error
        }
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
