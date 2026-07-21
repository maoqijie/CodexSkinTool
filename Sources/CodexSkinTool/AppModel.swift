import AppKit
import CodexSkinCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
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

    func refresh() {
        Task { await loadStatus() }
    }

    func requestApply() {
        if status.app.isRunning {
            showRestartConfirmation = true
        } else {
            apply(restart: true)
        }
    }

    func apply(restart: Bool) {
        runOperation {
            if self.isCustomSelected {
                _ = try await self.service.applyCustomAndRestart(self.customDraft)
            } else if restart {
                _ = try await self.service.applyAndRestart(themeID: self.selectedTheme.id)
            } else {
                _ = try await self.service.apply(themeID: self.selectedTheme.id)
            }
            return "已应用「\(self.selectedTheme.name)」"
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

    private func loadStatus() async {
        do {
            customDraft = try await service.customTheme()
            customBackgroundURL = await service.backgroundURL(for: customDraft)
            status = try await service.status()
            if let activeID = status.selectedThemeID,
               activeID == "custom" || themes.contains(where: { $0.id == activeID }) {
                selectedThemeID = activeID
            }
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
