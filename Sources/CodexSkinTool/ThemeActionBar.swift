import SwiftUI

struct ThemeActionBar: View {
    @EnvironmentObject private var model: AppModel
    let applyTitle: String
    let apply: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let message = model.message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppPalette.success)
            }
            Spacer()
            if model.status.canRestore {
                Button("恢复原始外观", systemImage: "arrow.uturn.backward") { model.restore() }
                    .disabled(model.isBusy)
            }
            if model.status.backgroundSkin.active {
                Label("图片皮肤已启用", systemImage: "photo.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppPalette.accent)
            }
            Button(action: apply) {
                if model.isBusy {
                    ProgressView().controlSize(.small).frame(minWidth: 100)
                } else {
                    Label(applyTitle, systemImage: "paintbrush.fill").frame(minWidth: 100)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppPalette.accent)
            .disabled(model.isBusy || !model.status.app.isInstalled || model.selectedItem == nil)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .background(.bar)
    }

}
