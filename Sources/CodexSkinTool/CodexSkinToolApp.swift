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
            CommandMenu("主题") {
                Button("应用所选主题") { model.requestApply() }
                    .keyboardShortcut(.return, modifiers: [.command])
                Button("恢复原始外观") { model.restore() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
