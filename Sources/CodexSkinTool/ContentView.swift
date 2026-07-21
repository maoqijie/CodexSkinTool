import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var updateChecker = UpdateChecker()

    var body: some View {
        NavigationSplitView {
            AppSidebar(updateChecker: updateChecker)
        } detail: {
            switch model.selectedSection {
            case .themes:
                ThemeGalleryView()
            case .settings:
                SettingsView()
            case .about:
                AboutView(updateChecker: updateChecker)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task { await updateChecker.checkForUpdates() }
        .alert("重启 Codex 并应用主题？", isPresented: $model.showRestartConfirmation) {
            Button("取消", role: .cancel) { model.cancelPendingApply() }
            Button("重启并应用") { model.confirmPendingApply() }
        } message: {
            Text("重启可能丢失尚未发送的输入。项目、对话和账号数据不会被修改。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
    }
}
