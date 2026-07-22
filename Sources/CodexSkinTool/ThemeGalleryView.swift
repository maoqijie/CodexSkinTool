import CodexSkinCore
import SwiftUI

struct ThemeGalleryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter = ThemeLibraryFilter.all

    private var builtIns: [ThemeLibraryItem] { model.themeItems.filter { $0.kind == .builtIn } }
    private var customs: [ThemeLibraryItem] { model.themeItems.filter { $0.kind == .custom } }
    private var recent: [ThemeLibraryItem] {
        model.recentThemeIDs.compactMap { id in model.themeItems.first { $0.id == id } }
    }
    private var visibleItems: [ThemeLibraryItem] {
        switch filter {
        case .all: model.themeItems
        case .custom: customs
        case .recent: recent
        }
    }
    private var visibleSelection: ThemeLibraryItem? {
        visibleItems.first { $0.id == model.selectedThemeID } ?? visibleItems.first
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if let selected = visibleSelection {
                    gallery(selected: selected)
                } else if model.themeItems.isEmpty {
                    emptyLibrary
                } else {
                    emptyFilter
                }
            }
            Divider()
            ThemeActionBar(applyTitle: "应用主题", selectionAvailable: visibleSelection != nil) {
                model.requestApply()
            }
        }
        .background(AppPalette.canvas)
        .navigationTitle("换肤")
        .onAppear {
            model.prepareThemeGallery()
            synchronizeSelection()
        }
        .onChange(of: filter) { _, _ in synchronizeSelection() }
        .onChange(of: model.themeItems) { _, _ in synchronizeSelection() }
        .alert("删除主题？", isPresented: Binding(
            get: { model.themePendingDeletion != nil },
            set: { if !$0 { model.cancelThemeDeletion() } }
        )) {
            Button("取消", role: .cancel) { model.cancelThemeDeletion() }
            Button("删除", role: .destructive) { model.confirmThemeDeletion() }
        } message: {
            Text(deleteMessage)
        }
    }

    private func gallery(selected: ThemeLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            filterControl
            switch filter {
            case .all:
                if !builtIns.isEmpty { themeSection("内置主题", items: builtIns) }
                if !customs.isEmpty { themeSection("我的主题", items: customs) }
            case .custom:
                themeSection("我的主题", items: customs)
            case .recent:
                themeSection("最近使用", items: recent)
            }

            Text("界面预览").font(.system(size: 13, weight: .semibold))
            ThemePreview(
                theme: selected.theme,
                backgroundURL: backgroundURL(for: selected),
                backgroundOpacity: selected.customDraft?.backgroundOpacity ?? 0.28,
                backgroundBlur: selected.customDraft?.backgroundBlur ?? 0,
                backgroundFit: selected.customDraft?.backgroundFit ?? .cover,
                backgroundBrightness: selected.customDraft?.backgroundBrightness ?? 1,
                backgroundFocusX: selected.customDraft?.backgroundFocusX ?? 0.5,
                backgroundFocusY: selected.customDraft?.backgroundFocusY ?? 0.5
            )
            .frame(maxWidth: 760, maxHeight: 320)
            themeDetails(selected.theme)
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private var filterControl: some View {
        Picker("主题筛选", selection: $filter) {
            ForEach(ThemeLibraryFilter.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 240)
    }

    private func themeSection(_ title: String, items: [ThemeLibraryItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(items.count) 套").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                ForEach(items) { item in
                    ThemeChoice(
                        item: item,
                        selected: model.selectedThemeID == item.id,
                        active: model.status.selectedThemeID == item.id,
                        select: { model.selectedThemeID = item.id },
                        delete: { model.requestDelete(item) }
                    )
                }
            }
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 14) {
            Image(systemName: "paintbrush")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("主题库为空").font(.system(size: 15, weight: .semibold))
            Text("可以恢复内置主题，或前往设置保存自己的主题。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button("恢复内置主题", systemImage: "arrow.counterclockwise") { model.restoreBuiltInThemes() }
                Button("前往设置", systemImage: "slider.horizontal.3") { model.selectedSection = .settings }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private var emptyFilter: some View {
        VStack(spacing: 12) {
            Image(systemName: filter == .custom ? "square.stack.3d.up.slash" : "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(filter == .custom ? "还没有我的主题" : "还没有最近使用的主题")
                .font(.system(size: 14, weight: .semibold))
            if filter == .custom {
                Button("前往设置", systemImage: "slider.horizontal.3") { model.selectedSection = .settings }
            } else {
                Button("查看全部", systemImage: "square.grid.2x2") { filter = .all }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private func synchronizeSelection() {
        guard let first = visibleSelection else { return }
        if model.selectedThemeID != first.id { model.selectedThemeID = first.id }
    }

    private func backgroundURL(for item: ThemeLibraryItem) -> URL? {
        guard let draft = item.customDraft else { return nil }
        return model.backgroundURL(for: draft)
    }

    private func themeDetails(_ theme: Theme) -> some View {
        HStack(alignment: .top, spacing: 28) {
            detailItem("代码主题", theme.codeThemeId, "chevron.left.forwardslash.chevron.right")
            detailItem("外观模式", theme.mode == .dark ? "深色" : "浅色", theme.mode == .dark ? "moon" : "sun.max")
            detailItem("窗口材质", theme.chromeTheme.opaqueWindows ? "不透明" : "通透", "macwindow")
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

    private var deleteMessage: String {
        guard let item = model.themePendingDeletion else { return "" }
        return item.kind == .builtIn
            ? "「\(item.theme.name)」会从本机主题库隐藏，可在设置中恢复。"
            : "「\(item.theme.name)」及其保存的背景图片将被删除。"
    }
}

private enum ThemeLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case custom
    case recent

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部"
        case .custom: "我的"
        case .recent: "最近"
        }
    }
}

private struct ThemeChoice: View {
    let item: ThemeLibraryItem
    let selected: Bool
    let active: Bool
    let select: () -> Void
    let delete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        ThemeSwatches(theme: item.theme, size: 10)
                        if active {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppPalette.success)
                                .accessibilityLabel("当前主题")
                        }
                        Spacer()
                    }
                    Text(item.theme.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary).lineLimit(1)
                    Text(item.theme.description)
                        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(10)
                .padding(.trailing, 20)
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

            Button(action: delete) { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(9)
                .help("删除主题")
                .accessibilityLabel("删除 \(item.theme.name)")
        }
    }
}
