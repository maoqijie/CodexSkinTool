import AppKit
import CodexSkinCore
import Foundation

func checkThemeLibrary() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexSkinLibraryChecks-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = CustomThemeStore(supportDirectoryURL: root)
    let library = ThemeLibraryStore(supportDirectoryURL: root)

    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 320,
        pixelsHigh: 240,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CheckFailure.failed("无法生成资料库图片夹具")
    }
    let source = root.appendingPathComponent("library-source.png")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try png.write(to: source)

    var draft = CustomThemeDraft(name: "保存主题")
    draft.backgroundImageName = try imageStore.importBackground(from: source)
    let originalDraftImage = draft.backgroundImageName
    let saved = try library.saveCustom(draft)
    try expect(saved.id.hasPrefix("user-"), "自定义主题 ID 前缀错误")
    try expect(saved.draft.backgroundImageName != originalDraftImage, "保存主题未复制背景图片")
    try expect(imageStore.backgroundURL(named: saved.draft.backgroundImageName) != nil, "保存主题背景快照缺失")
    try expect(fileMode(library.libraryURL) == 0o600, "主题资料库权限不是 0600")

    try imageStore.removeBackground(named: originalDraftImage)
    try expect(imageStore.backgroundURL(named: saved.draft.backgroundImageName) != nil, "草稿图片删除影响保存主题")
    try expect(try library.items().contains(where: { $0.id == saved.id && $0.kind == .custom }), "保存主题未进入资料库")

    var replacement = draft
    replacement.name = "覆盖主题"
    replacement.backgroundImageName = try imageStore.importBackground(from: source)
    let oldSnapshot = saved.draft.backgroundImageName
    let updated = try library.saveCustom(replacement, replacing: saved.id)
    try expect(updated.id == saved.id, "覆盖保存改变了主题 ID")
    try expect(imageStore.backgroundURL(named: oldSnapshot) == nil, "覆盖保存未清理旧背景快照")

    let updatedImage = updated.draft.backgroundImageName
    try library.delete(itemID: updated.id)
    try expect(imageStore.backgroundURL(named: updatedImage) == nil, "自定义主题删除未清理背景快照")
    for theme in ThemeCatalog.builtIn { try library.delete(itemID: theme.id) }
    try expect(try library.items().isEmpty, "删除全部主题后资料库不为空")
    try library.restoreBuiltIns()
    try expect(try library.items().count == ThemeCatalog.builtIn.count, "内置主题恢复失败")

    var missingSource = CustomThemeDraft(name: "失效图片")
    missingSource.backgroundImageName = "missing.png"
    do {
        _ = try library.saveCustom(missingSource)
        throw CheckFailure.failed("保存主题时未拒绝失效背景图片")
    } catch ThemeServiceError.invalidBackground {
        // Expected.
    }

    let corruptRoot = root.appendingPathComponent("corrupt")
    let corruptImageStore = CustomThemeStore(supportDirectoryURL: corruptRoot)
    let corruptLibrary = ThemeLibraryStore(supportDirectoryURL: corruptRoot)
    try FileManager.default.createDirectory(at: corruptRoot, withIntermediateDirectories: true)
    let sharedName = try corruptImageStore.importBackground(from: source)
    var first = CustomThemeDraft(name: "主题一")
    first.backgroundImageName = sharedName
    var second = CustomThemeDraft(name: "主题二")
    second.backgroundImageName = sharedName
    let corruptState = ThemeLibraryState(customThemes: [
        SavedCustomTheme(id: "user-one", draft: first),
        SavedCustomTheme(id: "user-two", draft: second),
    ])
    try JSONEncoder().encode(corruptState).write(to: corruptLibrary.libraryURL)
    do {
        _ = try corruptLibrary.loadState()
        throw CheckFailure.failed("主题资料库未拒绝重复背景图片引用")
    } catch ThemeServiceError.invalidState {
        // Expected.
    }

    second.backgroundImageName = "missing.png"
    let missingState = ThemeLibraryState(customThemes: [
        SavedCustomTheme(id: "user-one", draft: first),
        SavedCustomTheme(id: "user-two", draft: second),
    ])
    try JSONEncoder().encode(missingState).write(to: corruptLibrary.libraryURL)
    do {
        _ = try corruptLibrary.loadState()
        throw CheckFailure.failed("主题资料库未拒绝缺失背景图片引用")
    } catch ThemeServiceError.invalidState {
        // Expected.
    }
}
