import CodexSkinCore
import SwiftUI

struct ThemeGalleryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "换肤",
                subtitle: "选择内置主题并预览 Codex 界面"
            ) {
                ThemeSwatches(theme: model.selectedTheme, size: 16)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle("主题库", detail: "\(model.themes.count) 套")
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 132), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(model.themes) { theme in
                            ThemeChoice(
                                theme: theme,
                                selected: model.selectedThemeID == theme.id,
                                active: model.status.selectedThemeID == theme.id
                            ) {
                                model.selectedThemeID = theme.id
                            }
                        }
                    }

                    sectionTitle("界面预览", detail: model.selectedTheme.name)
                    ThemePreview(theme: model.selectedTheme)
                        .frame(maxWidth: 760, maxHeight: 320)
                    themeDetails
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            Divider()
            ThemeActionBar(applyTitle: "应用主题") { model.requestApply() }
        }
        .background(AppPalette.canvas)
        .navigationTitle("换肤")
        .onAppear { model.prepareThemeGallery() }
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var themeDetails: some View {
        HStack(alignment: .top, spacing: 28) {
            detailItem("代码主题", model.selectedTheme.codeThemeId, "chevron.left.forwardslash.chevron.right")
            detailItem("外观模式", model.selectedTheme.mode == .dark ? "深色" : "浅色", model.selectedTheme.mode == .dark ? "moon" : "sun.max")
            detailItem("窗口材质", model.selectedTheme.chromeTheme.opaqueWindows ? "不透明" : "通透", "macwindow")
            Spacer()
        }
    }

    private func detailItem(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(AppPalette.accent).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 12, weight: .medium))
            }
        }
    }
}

private struct ThemeChoice: View {
    let theme: Theme
    let selected: Bool
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    ThemeSwatches(theme: theme, size: 10)
                    Spacer()
                    if active {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppPalette.success)
                            .accessibilityLabel("当前主题")
                    }
                }
                Text(theme.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(theme.description)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(selected ? AppPalette.accent.opacity(0.08) : AppPalette.panel)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(selected ? AppPalette.accent : AppPalette.line, lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("选择并预览此主题")
    }
}
