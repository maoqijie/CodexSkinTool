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

private enum ApplyTarget {
    case builtIn(Theme)
    case custom(CustomThemeDraft)

    var name: String {
        switch self {
        case .builtIn(let theme): theme.name
        case .custom(let draft): draft.theme.name
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection = AppSection.themes
    @Published var selectedThemeID: String
    @Published var status = ThemeServiceStatus.checking
    @Published var isBusy = false
    @Published var message: String?
    @Published var errorMessage: String?
    @Published var showRestartConfirmation = false
    @Published var customDraft = CustomThemeDraft()
    @Published var customBackgroundURL: URL?

    let themes: [Theme]
    private let service: ThemeService
    private let appService = CodexAppService()
    private var pendingApplyTarget: ApplyTarget?
    private var didLoadCustomDraft = false

    init(service: ThemeService) {
        self.service = service
        themes = ThemeCatalog.builtIn
        selectedThemeID = themes.first?.id ?? ""
    }

    var selectedTheme: Theme {
        if selectedThemeID == "custom" { return customDraft.theme }
        return themes.first(where: { $0.id == selectedThemeID }) ?? themes[0]
    }

    var isCustomSelected: Bool { selectedThemeID == "custom" }
    var isAboutSelected: Bool { selectedSection == .about }

    func refresh() {
        Task { await loadStatus(loadCustomDraft: !didLoadCustomDraft) }
    }

    func requestApply() {
        requestApply(target: .builtIn(selectedTheme))
    }

    func requestApplyCustom() {
        selectedThemeID = "custom"
        requestApply(target: .custom(customDraft))
    }

    func requestApplyForCurrentPage() {
        selectedSection == .settings ? requestApplyCustom() : requestApply()
    }

    func prepareThemeGallery() {
        guard isCustomSelected else { return }
        selectedThemeID = themes.first?.id ?? ""
    }

    func prepareSettings() {
        selectedThemeID = "custom"
    }

    func confirmPendingApply() {
        guard let target = pendingApplyTarget else { return }
        pendingApplyTarget = nil
        performApply(target)
    }

    func cancelPendingApply() {
        pendingApplyTarget = nil
    }

    private func requestApply(target: ApplyTarget) {
        pendingApplyTarget = target
        if status.app.isRunning {
            showRestartConfirmation = true
        } else {
            pendingApplyTarget = nil
            performApply(target)
        }
    }

    private func performApply(_ target: ApplyTarget) {
        runOperation {
            switch target {
            case .builtIn(let theme):
                _ = try await self.service.applyAndRestart(themeID: theme.id)
            case .custom(let draft):
                _ = try await self.service.applyCustomAndRestart(draft)
            }
            return "已应用「\(target.name)」"
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
            self.customDraft = try await self.service.importBackground(from: url, into: self.customDraft)
            self.customBackgroundURL = await self.service.backgroundURL(for: self.customDraft)
            self.selectedThemeID = "custom"
            return "已导入背景图片"
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

    private func runOperation(_ operation: @escaping () async throws -> String) {
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
            await loadStatus()
        }
    }

    private func loadStatus(loadCustomDraft: Bool = false) async {
        do {
            if loadCustomDraft {
                let draft = try await service.customTheme()
                customDraft = draft
                customBackgroundURL = await service.backgroundURL(for: draft)
                didLoadCustomDraft = true
            }
            status = try await service.status()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
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
