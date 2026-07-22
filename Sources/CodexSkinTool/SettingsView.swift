import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
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
            HStack(spacing: 10) {
                if let message = model.message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppPalette.success)
                        .lineLimit(1)
                }
                if model.hasHiddenBuiltIns {
                    Button("恢复内置主题", systemImage: "arrow.counterclockwise") {
                        model.restoreBuiltInThemes()
                    }
                    .disabled(model.isBusy)
                }
                Spacer()
                Button("保存到我的主题", systemImage: "square.and.arrow.down") {
                    model.saveCustomToLibrary()
                }
                .disabled(model.isBusy)
                Button("应用当前配置", systemImage: "paintbrush.fill") {
                    model.requestApplyCustom()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.accent)
                .disabled(model.isBusy || !model.status.app.isInstalled)
            }
            .padding(.horizontal, 20)
            .frame(height: 64)
            .background(.bar)
        }
        .background(AppPalette.canvas)
        .navigationTitle("设置")
    }
}
