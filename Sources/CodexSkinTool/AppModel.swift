import AppKit
import CodexSkinCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum AppSection: String, CaseIterable, Identifiable {
    case themes
    case settings
    case about

    var id: Self { self }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection = AppSection.themes
    @Published var selectedThemeID: String
    @Published var themeItems: [ThemeLibraryItem]
    @Published var status = ThemeServiceStatus.checking
    @Published var isBusy = false
    @Published var message: String?
    @Published var errorMessage: String?
    @Published var showRestartConfirmation = false
    @Published var customDraft = CustomThemeDraft()
    @Published var customBackgroundURL: URL?
    @Published private(set) var recentThemeIDs: [String]
    @Published private var libraryBackgroundURLs: [String: URL] = [:]
    @Published var themePendingDeletion: ThemeLibraryItem?

    private let service: ThemeService
    private let appService = CodexAppService()
    private var pendingApplyTarget: ThemeLibraryItem?
    private var didLoadCustomDraft = false

    init(service: ThemeService) {
        self.service = service
        recentThemeIDs = UserDefaults.standard.stringArray(forKey: Self.recentThemeIDsKey) ?? []
        let initialItems = ThemeCatalog.builtIn.map {
            ThemeLibraryItem(id: $0.id, kind: .builtIn, theme: $0)
        }
        themeItems = initialItems
        selectedThemeID = initialItems.first?.id ?? ""
    }

    var selectedItem: ThemeLibraryItem? { themeItems.first { $0.id == selectedThemeID } }
    var selectedTheme: Theme? { selectedItem?.theme }

    var isAboutSelected: Bool { selectedSection == .about }
    var hasHiddenBuiltIns: Bool { themeItems.filter { $0.kind == .builtIn }.count < ThemeCatalog.builtIn.count }

    func refresh() {
        Task { await loadStatus(loadCustomDraft: !didLoadCustomDraft) }
    }

    func requestApply() {
        guard let selectedItem else { return }
        requestApply(target: selectedItem)
    }

    func requestApplyCustom() {
        let draft = customDraft
        requestApply(target: ThemeLibraryItem(
            id: "custom",
            kind: .custom,
            theme: draft.theme,
            customDraft: draft
        ))
    }

    func requestApplyForCurrentPage() {
        selectedSection == .settings ? requestApplyCustom() : requestApply()
    }

    func prepareThemeGallery() {
        ensureThemeSelection()
    }

    func confirmPendingApply() {
        guard let target = pendingApplyTarget else { return }
        pendingApplyTarget = nil
        performApply(target)
    }

    func cancelPendingApply() {
        pendingApplyTarget = nil
    }

    private func requestApply(target: ThemeLibraryItem) {
        pendingApplyTarget = target
        if status.app.isRunning {
            showRestartConfirmation = true
        } else {
            pendingApplyTarget = nil
            performApply(target)
        }
    }

    private func performApply(_ target: ThemeLibraryItem) {
        runOperation {
            _ = try await self.service.applyAndRestart(target)
            self.recordThemeUsage(target.id)
            return "已应用「\(target.theme.name)」"
        }
    }

    func saveCustomToLibrary() {
        let draft = customDraft
        runOperation(reloadLibrary: true) {
            let saved = try await self.service.saveThemeToLibrary(draft)
            self.selectedThemeID = saved.id
            return "已保存「\(saved.theme.name)」"
        }
    }

    func requestDelete(_ item: ThemeLibraryItem) {
        themePendingDeletion = item
    }

    func cancelThemeDeletion() {
        themePendingDeletion = nil
    }

    func confirmThemeDeletion() {
        guard let item = themePendingDeletion else { return }
        themePendingDeletion = nil
        runOperation(reloadLibrary: true) {
            try await self.service.deleteTheme(itemID: item.id)
            return "已删除「\(item.theme.name)」"
        }
    }

    func restoreBuiltInThemes() {
        runOperation(reloadLibrary: true) {
            try await self.service.restoreBuiltInThemes()
            return "已恢复内置主题"
        }
    }

    func chooseBackground() {
        let panel = NSOpenPanel()
        panel.title = "选择背景图片"
        panel.prompt = "选择"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = importBackground(from: url)
    }

    @discardableResult
    func importBackground(from url: URL) -> Bool {
        guard !isBusy, url.isFileURL else { return false }
        runOperation {
            let previousAccent = self.customDraft.accent
            self.customDraft = try await self.service.importBackground(from: url, into: self.customDraft)
            self.customBackgroundURL = await self.service.backgroundURL(for: self.customDraft)
            return self.customDraft.accent == previousAccent ? "已导入背景图片" : "已导入图片并匹配强调色"
        }
        return true
    }

    func removeBackground() {
        runOperation {
            self.customDraft = try await self.service.removeBackground(from: self.customDraft)
            self.customBackgroundURL = nil
            return "已移除背景图片"
        }
    }

    func backgroundURL(for draft: CustomThemeDraft) -> URL? {
        guard let name = draft.backgroundImageName else { return nil }
        return libraryBackgroundURLs[name]
    }

    func restore() {
        runOperation {
            if self.status.app.isRunning {
                _ = try await self.service.restoreAndRestart()
            } else {
                _ = try await self.service.restore()
            }
            return "已恢复应用前的 Codex 外观"
        }
    }

    func openCodex() {
        Task {
            do {
                try appService.open()
                await loadStatus()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func runOperation(
        reloadLibrary: Bool = false,
        _ operation: @escaping () async throws -> String
    ) {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        errorMessage = nil
        Task {
            do {
                message = try await operation()
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
            await loadStatus(loadThemeLibrary: reloadLibrary)
        }
    }

    private func loadStatus(
        loadCustomDraft: Bool = false,
        loadThemeLibrary: Bool = true
    ) async {
        do {
            if loadCustomDraft {
                let draft = try await service.customTheme()
                customDraft = draft
                customBackgroundURL = await service.backgroundURL(for: draft)
                didLoadCustomDraft = true
            }
            if loadThemeLibrary {
                themeItems = try await service.themeLibrary()
                var urls: [String: URL] = [:]
                for item in themeItems {
                    if let draft = item.customDraft,
                       let name = draft.backgroundImageName,
                       let url = await service.backgroundURL(for: draft) {
                        urls[name] = url
                    }
                }
                libraryBackgroundURLs = urls
                ensureThemeSelection()
            }
            status = try await service.status()
            if let appliedID = status.selectedThemeID,
               themeItems.contains(where: { $0.id == appliedID }) {
                recordThemeUsage(appliedID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ensureThemeSelection() {
        guard !themeItems.contains(where: { $0.id == selectedThemeID }) else { return }
        selectedThemeID = themeItems.first?.id ?? ""
    }

    private func recordThemeUsage(_ id: String) {
        guard recentThemeIDs.first != id else { return }
        recentThemeIDs.removeAll { $0 == id }
        recentThemeIDs.insert(id, at: 0)
        recentThemeIDs = Array(recentThemeIDs.prefix(8))
        UserDefaults.standard.set(recentThemeIDs, forKey: Self.recentThemeIDsKey)
    }

    private static let recentThemeIDsKey = "recentThemeIDs"

}

extension ThemeServiceStatus {
    static var checking: ThemeServiceStatus {
        ThemeServiceStatus(
            selectedThemeID: nil,
            configExists: false,
            canRestore: false,
            needsRestart: false,
            app: CodexAppStatus(isInstalled: false, appURL: nil, version: nil, isRunning: false)
        )
    }

    var title: String {
        guard app.isInstalled else { return "未找到 Codex Desktop" }
        return app.isRunning ? "Codex 正在运行" : "Codex 已安装"
    }

    var detail: String {
        app.version.map { "版本 \($0)" } ?? "等待状态刷新"
    }
}
