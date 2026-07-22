import SwiftUI

struct AppSidebar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var updateChecker: UpdateChecker
    @State private var hoveredSection: AppSection?
    @FocusState private var focusedSection: AppSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            productHeader

            VStack(spacing: 4) {
                ForEach(AppSection.allCases) { section in
                    navigationButton(for: section)
                }
            }

            Spacer(minLength: 20)
            statusPanel
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(.thinMaterial)
        .navigationSplitViewColumnWidth(min: 176, ideal: 188, max: 210)
        .navigationTitle("Codex Skin")
    }

    private var productHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "paintbrush.pointed.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Codex Skin")
                    .font(.system(size: 14, weight: .semibold))
                Text("外观管理")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 18)
        .accessibilityElement(children: .combine)
    }

    private func navigationButton(for section: AppSection) -> some View {
        let isSelected = model.selectedSection == section
        let isHovered = hoveredSection == section
        let isFocused = focusedSection == section

        return Button {
            model.selectedSection = section
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? Color.accentColor : .clear)
                    .frame(width: 3, height: 18)

                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)

                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))

                Spacer(minLength: 8)

                if section == .about, case .updateAvailable = updateChecker.state {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tint)
                        .accessibilityLabel("有新版本")
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .frame(maxWidth: .infinity, minHeight: 34)
            .padding(.horizontal, 8)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(navigationBackground(isSelected: isSelected, isHovered: isHovered))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isFocused ? Color.accentColor.opacity(0.8) : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .focused($focusedSection, equals: section)
        .onHover { isHovering in
            hoveredSection = isHovering ? section : nil
        }
        .keyboardShortcut(section.shortcut, modifiers: [.command])
        .accessibilityLabel(accessibilityLabel(for: section))
        .accessibilityValue(isSelected ? "当前页面" : "")
        .accessibilityHint("切换到\(section.title)页面")
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private func navigationBackground(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        return isHovered ? Color.primary.opacity(0.055) : .clear
    }

    private func accessibilityLabel(for section: AppSection) -> String {
        if section == .about, case .updateAvailable = updateChecker.state {
            return "关于，有新版本"
        }
        return section.title
    }

    private var statusPanel: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.status.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(model.status.detail)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button { model.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
            .help("刷新状态")
            .accessibilityLabel("刷新 Codex 状态")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .help("\(model.status.title) · \(model.status.detail)")
    }

    private var statusColor: Color {
        guard model.status.app.isInstalled else { return .red }
        return model.status.app.isRunning ? AppPalette.success : .secondary
    }
}

private extension AppSection {
    var title: String {
        switch self {
        case .themes: "换肤"
        case .settings: "设置"
        case .about: "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .themes: "paintbrush"
        case .settings: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .themes: "1"
        case .settings: "2"
        case .about: "3"
        }
    }
}
