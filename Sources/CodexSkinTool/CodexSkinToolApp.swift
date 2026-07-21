import CodexSkinCore
import SwiftUI

@main
struct CodexSkinToolApp: App {
    @StateObject private var model: AppModel

    init() {
        _model = StateObject(wrappedValue: AppModel(service: ThemeService()))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 880, minHeight: 580)
                .onAppear { model.refresh() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("关于 CodexSkinTool") { model.selectedSection = .about }
            }
            CommandMenu("主题") {
                Button("应用当前页面主题") { model.requestApplyForCurrentPage() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(model.isAboutSelected)
                Button("恢复原始外观") { model.restore() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
