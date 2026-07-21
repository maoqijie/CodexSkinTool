import CodexSkinCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            themeSidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .alert("重启 Codex 并应用主题？", isPresented: $model.showRestartConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重启并应用") { model.apply(restart: true) }
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

    private var themeSidebar: some View {
        List(selection: $model.selectedThemeID) {
            Section("内置主题") {
                ForEach(model.themes) { theme in
                    ThemeRow(theme: theme, active: model.status.selectedThemeID == theme.id)
                        .tag(theme.id)
                }
            }
            Section("自定义") {
                ThemeRow(theme: model.customDraft.theme, active: model.status.selectedThemeID == "custom")
                    .tag("custom")
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 210, ideal: 226, max: 260)
        .navigationTitle("Codex 换肤")
        .safeAreaInset(edge: .bottom) {
            statusBar
        }
    }

    private var statusBar: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                Circle()
                    .fill(model.status.app.isInstalled ? (model.status.app.isRunning ? AppPalette.success : .secondary) : .red)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.status.title)
                        .font(.system(size: 12, weight: .medium))
                    Text(model.status.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("刷新状态")
                .accessibilityLabel("刷新 Codex 状态")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(.bar)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ThemePreview(
                        theme: model.selectedTheme,
                        backgroundURL: model.isCustomSelected ? model.customBackgroundURL : nil,
                        backgroundOpacity: model.customDraft.backgroundOpacity,
                        backgroundBlur: model.customDraft.backgroundBlur,
                        backgroundFit: model.customDraft.backgroundFit
                    )
                        .frame(maxWidth: 760)
                    if model.isCustomSelected {
                        CustomThemeEditor(
                            draft: $model.customDraft,
                            backgroundURL: model.customBackgroundURL,
                            chooseBackground: model.chooseBackground,
                            removeBackground: model.removeBackground
                        )
                        .frame(maxWidth: 760)
                    } else {
                        themeDetails
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            Divider()
            actionBar
        }
        .background(AppPalette.canvas)
        .navigationTitle(model.selectedTheme.name)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.selectedTheme.name)
                    .font(.system(size: 18, weight: .semibold))
                Text(model.selectedTheme.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ThemeSwatches(theme: model.selectedTheme, size: 16)
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
        .background(.bar)
    }

    private var themeDetails: some View {
        HStack(alignment: .top, spacing: 28) {
            detailItem("代码主题", model.selectedTheme.codeThemeId, icon: "chevron.left.forwardslash.chevron.right")
            detailItem("外观模式", model.selectedTheme.mode == .dark ? "深色" : "浅色", icon: model.selectedTheme.mode == .dark ? "moon" : "sun.max")
            detailItem("窗口材质", model.selectedTheme.chromeTheme.opaqueWindows ? "不透明" : "通透", icon: "macwindow")
            Spacer()
        }
    }

    private func detailItem(_ title: String, _ value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(AppPalette.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 12, weight: .medium))
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if let message = model.message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppPalette.success)
                    .transition(.opacity)
            } else {
                Text("配置会先备份，再原子写入；不会修改 Codex 安装包。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.status.canRestore {
                Button("恢复原始外观", systemImage: "arrow.uturn.backward") {
                    model.restore()
                }
                .disabled(model.isBusy)
            }
            if model.status.backgroundSkin.active {
                Label("图片皮肤已启用", systemImage: "photo.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppPalette.accent)
            }
            if !model.status.app.isRunning && model.status.app.isInstalled {
                Button("打开 Codex", systemImage: "arrow.up.forward.app") {
                    model.openCodex()
                }
                .disabled(model.isBusy)
            }
            Button {
                model.requestApply()
            } label: {
                if model.isBusy {
                    ProgressView().controlSize(.small).frame(minWidth: 90)
                } else {
                    Label("一键应用", systemImage: "paintbrush.fill")
                        .frame(minWidth: 90)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppPalette.accent)
            .disabled(model.isBusy || !model.status.app.isInstalled)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .background(.bar)
    }
}

private struct ThemeRow: View {
    let theme: Theme
    let active: Bool

    var body: some View {
        HStack(spacing: 10) {
            ThemeSwatches(theme: theme, size: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.name)
                    .font(.system(size: 12, weight: .medium))
                Text(theme.description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if active {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppPalette.success)
                    .accessibilityLabel("当前主题")
            }
        }
        .padding(.vertical, 4)
    }
}
