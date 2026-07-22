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
    draft.backgroundImageName = try imageStore.importBackground(from: source).imageName
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
    replacement.backgroundImageName = try imageStore.importBackground(from: source).imageName
    let oldSnapshot = saved.draft.backgroundImageName
    let updated = try library.saveCustom(replacement, replacing: saved.id)
    try expect(updated.id == saved.id, "覆盖保存改变了主题 ID")
    try expect(imageStore.backgroundURL(named: oldSnapshot) == nil, "覆盖保存未清理旧背景快照")

    let renamed = try library.renameCustom(itemID: updated.id, name: "  新主题名  ")
    try expect(renamed.id == updated.id, "重命名改变了主题 ID")
    try expect(renamed.theme.name == "新主题名", "重命名未去除首尾空白")
    try expect(renamed.draft.backgroundImageName == updated.draft.backgroundImageName, "重命名改变了背景图片")
    try expect(imageStore.backgroundURL(named: renamed.draft.backgroundImageName) != nil, "重命名删除了背景图片")
    try expect(try library.items().first(where: { $0.id == updated.id })?.theme.name == "新主题名", "重命名未持久化")
    do {
        _ = try library.renameCustom(itemID: updated.id, name: "   ")
        throw CheckFailure.failed("重命名未拒绝空名称")
    } catch ThemeServiceError.invalidState {
        // Expected.
    }
    do {
        _ = try library.renameCustom(itemID: updated.id, name: "无效\n名称")
        throw CheckFailure.failed("重命名未拒绝控制字符")
    } catch ThemeServiceError.invalidState {
        // Expected.
    }
    do {
        _ = try library.renameCustom(itemID: updated.id, name: String(repeating: "名", count: 41))
        throw CheckFailure.failed("重命名未拒绝超长名称")
    } catch ThemeServiceError.invalidState {
        // Expected.
    }
    let boundaryName = String(repeating: "名", count: 40)
    try expect(try library.renameCustom(itemID: updated.id, name: boundaryName).theme.name == boundaryName, "重命名错误拒绝 40 字名称")
    _ = try library.renameCustom(itemID: updated.id, name: "新主题名")
    do {
        _ = try library.renameCustom(itemID: ThemeCatalog.builtIn[0].id, name: "不能修改")
        throw CheckFailure.failed("重命名未拒绝内置主题")
    } catch ThemeServiceError.invalidState {
        // Expected.
    }
    try expect(try library.items().first(where: { $0.id == updated.id })?.theme.name == "新主题名", "失败的重命名改变了原名称")

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
    let sharedName = try corruptImageStore.importBackground(from: source).imageName
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
