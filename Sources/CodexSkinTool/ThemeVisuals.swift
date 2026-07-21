import SwiftUI
import CodexSkinCore

enum AppPalette {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let line = Color(nsColor: .separatorColor)
    static let muted = Color.secondary
    static let accent = Color(red: 0.082, green: 0.357, blue: 0.816)
    static let success = Color(red: 0.12, green: 0.58, blue: 0.31)
}

extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

struct ThemeSwatches: View {
    let theme: Theme
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 3) {
            ForEach(previewColors, id: \.self) { color in
                Circle()
                    .fill(Color(hex: color))
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 0.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(theme.name) 配色")
    }

    private var previewColors: [String] {
        [theme.chromeTheme.accent, theme.chromeTheme.surface, theme.chromeTheme.ink]
    }
}

struct ThemePreview: View {
    let theme: Theme

    private var surface: Color { Color(hex: theme.chromeTheme.surface) }
    private var ink: Color { Color(hex: theme.chromeTheme.ink) }
    private var accent: Color { Color(hex: theme.chromeTheme.accent) }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                sidebar(width: max(118, proxy.size.width * 0.27))
                workspace
            }
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ink.opacity(0.13), lineWidth: 1)
            }
        }
        .aspectRatio(1.52, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(theme.name) 主题预览")
    }

    private func sidebar(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .foregroundStyle(accent)
                Text("Codex")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.bottom, 6)

            sidebarItem("square.and.pencil", "新建任务", selected: true)
            sidebarItem("tray", "收件箱", selected: false)
            sidebarItem("clock", "自动化", selected: false)

            Divider().overlay(ink.opacity(0.12))
            Text("项目")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(ink.opacity(0.45))
            sidebarItem("folder", "CodexSkinTool", selected: false)
            Spacer()
            sidebarItem("gearshape", "设置", selected: false)
        }
        .font(.system(size: 10))
        .foregroundStyle(ink.opacity(0.84))
        .padding(12)
        .frame(width: width, alignment: .topLeading)
        .background(ink.opacity(theme.mode == .dark ? 0.08 : 0.035))
        .overlay(alignment: .trailing) { Rectangle().fill(ink.opacity(0.1)).frame(width: 1) }
    }

    private func sidebarItem(_ icon: String, _ title: String, selected: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).frame(width: 12)
            Text(title).lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 25, alignment: .leading)
        .background(selected ? accent.opacity(theme.mode == .dark ? 0.22 : 0.12) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("新任务")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Image(systemName: "ellipsis")
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.09)).frame(height: 1) }

            VStack(alignment: .leading, spacing: 12) {
                Spacer()
                Text("今天想构建什么？")
                    .font(.system(size: 18, weight: .semibold))
                Text("描述任务，Codex 会在你的项目中完成工作。")
                    .font(.system(size: 10))
                    .foregroundStyle(ink.opacity(0.55))
                composer
                Spacer()
            }
            .padding(.horizontal, 22)
        }
        .foregroundStyle(ink)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("让 Codex 优化这个项目的主题切换体验")
                .font(.system(size: 10))
                .foregroundStyle(ink.opacity(0.68))
            HStack {
                Image(systemName: "plus")
                Text("本地")
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(ink.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Spacer()
                Image(systemName: "arrow.up")
                    .foregroundStyle(surface)
                    .frame(width: 22, height: 22)
                    .background(accent)
                    .clipShape(Circle())
            }
            .font(.system(size: 9, weight: .medium))
        }
        .padding(12)
        .background(ink.opacity(theme.mode == .dark ? 0.08 : 0.035))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(ink.opacity(0.15), lineWidth: 1)
        }
    }
}
