import AppKit
import CodexSkinCore
import SwiftUI

struct CustomThemeEditor: View {
    @Binding var draft: CustomThemeDraft
    let backgroundURL: URL?
    let chooseBackground: () -> Void
    let importBackground: (URL) -> Bool
    let removeBackground: () -> Void
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("自定义主题")
                .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 16) {
                field("名称") {
                    TextField("我的主题", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                }
                field("外观") {
                    Picker("外观", selection: $draft.mode) {
                        Text("浅色").tag(ThemeMode.light)
                        Text("深色").tag(ThemeMode.dark)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                field("代码主题") {
                    Picker("代码主题", selection: $draft.codeThemeID) {
                        ForEach(ThemeCatalog.supportedCodeThemeIDs, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
            }

            HStack(spacing: 24) {
                colorControl("强调色", value: $draft.accent)
                colorControl("文字色", value: $draft.ink)
                colorControl("背景色", value: $draft.surface)
                field("对比度 \(draft.contrast)") {
                    Slider(value: contrastBinding, in: 0...100, step: 1)
                        .frame(width: 130)
                }
            }

            Divider()

            HStack(alignment: .center, spacing: 14) {
                Image(systemName: isDropTarget ? "square.and.arrow.down.fill" : backgroundURL == nil ? "photo.badge.plus" : "photo.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(AppPalette.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDropTarget ? "松开即可导入" : backgroundURL?.lastPathComponent ?? "拖入图片，或选择本地文件")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text("PNG、JPEG、HEIC、TIFF 或 WebP，最大 16 MB")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if backgroundURL != nil {
                    Button("移除", systemImage: "trash", role: .destructive, action: removeBackground)
                }
                Button(backgroundURL == nil ? "选择图片" : "更换图片", systemImage: "photo.on.rectangle", action: chooseBackground)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isDropTarget ? AppPalette.accent.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        isDropTarget ? AppPalette.accent : AppPalette.line,
                        style: StrokeStyle(lineWidth: isDropTarget ? 2 : 1, dash: [6, 4])
                    )
            }
            .contentShape(Rectangle())
            .dropDestination(for: URL.self) { urls, _ in
                guard urls.count == 1, let url = urls.first else { return false }
                return importBackground(url)
            } isTargeted: { targeted in
                isDropTarget = targeted
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("背景图片")
            .accessibilityValue(backgroundURL == nil ? "未选择" : "已选择")
            .accessibilityHint("可将单张本地图片拖入此区域，或使用选择图片按钮")

            if backgroundURL != nil {
                HStack(spacing: 22) {
                    field("显示方式") {
                        Picker("显示方式", selection: $draft.backgroundFit) {
                            ForEach(BackgroundFit.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    field("透明度 \(Int(draft.backgroundOpacity * 100))%") {
                        Slider(value: $draft.backgroundOpacity, in: 0.08...0.85)
                            .frame(width: 150)
                    }
                    field("模糊 \(Int(draft.backgroundBlur))") {
                        Slider(value: $draft.backgroundBlur, in: 0...24, step: 1)
                            .frame(width: 130)
                    }
                }
            }
        }
        .padding(16)
        .background(AppPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 7).stroke(AppPalette.line, lineWidth: 1) }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            content()
        }
    }

    private func colorControl(_ title: String, value: Binding<String>) -> some View {
        field(title) {
            ColorPicker(title, selection: Binding(
                get: { Color(hex: value.wrappedValue) },
                set: { value.wrappedValue = $0.hexString ?? value.wrappedValue }
            ), supportsOpacity: false)
            .labelsHidden()
        }
    }

    private var contrastBinding: Binding<Double> {
        Binding(get: { Double(draft.contrast) }, set: { draft.contrast = Int($0) })
    }
}

extension Color {
    var hexString: String? {
        guard let color = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }
}
