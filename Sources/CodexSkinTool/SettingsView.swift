import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "设置",
                subtitle: "自定义配色、代码主题与图片背景"
            ) {
                ThemeSwatches(theme: model.customDraft.theme, size: 16)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ThemePreview(
                        theme: model.customDraft.theme,
                        backgroundURL: model.customBackgroundURL,
                        backgroundOpacity: model.customDraft.backgroundOpacity,
                        backgroundBlur: model.customDraft.backgroundBlur,
                        backgroundFit: model.customDraft.backgroundFit
                    )
                    .frame(maxWidth: 760, maxHeight: 320)

                    CustomThemeEditor(
                        draft: $model.customDraft,
                        backgroundURL: model.customBackgroundURL,
                        chooseBackground: model.chooseBackground,
                        importBackground: model.importBackground,
                        removeBackground: model.removeBackground
                    )
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            Divider()
            ThemeActionBar(applyTitle: "应用自定义主题") { model.requestApplyCustom() }
        }
        .background(AppPalette.canvas)
        .navigationTitle("设置")
        .onAppear { model.prepareSettings() }
    }
}
