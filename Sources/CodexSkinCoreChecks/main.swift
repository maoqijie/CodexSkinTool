import Darwin
import Foundation
import AppKit
import CodexSkinCore

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self { case .failed(let message): message }
    }
}

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw CheckFailure.failed(message) }
}

func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw CheckFailure.failed(message) }
    return value
}

func edit(_ source: String, themeID: String) throws -> String {
    let theme = try require(ThemeCatalog.theme(id: themeID), "缺少内置主题 \(themeID)")
    let data = try TOMLDocumentEditor().applying(theme: theme, to: Data(source.utf8))
    return try require(String(data: data, encoding: .utf8), "编辑结果不是 UTF-8")
}

func occurrences(of needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
}

func checkEditor() throws {
    let source = """
    # 顶部注释
    model = "gpt-5"

    [desktop]
    localeOverride = "zh-CN" # 保留

    [projects."/tmp/demo"]
    trust_level = "trusted"
    """
    let edited = try edit(source, themeID: "github-light")
    try expect(edited.contains("localeOverride = \"zh-CN\" # 保留"), "未保留 desktop 未知配置")
    try expect(edited.contains("[projects.\"/tmp/demo\"]\ntrust_level = \"trusted\""), "未保留其他段落")
    try expect(edited.contains("appearanceTheme = \"light\""), "未写入外观模式")
    try expect(edited.contains("appearanceLightCodeThemeId = \"github\""), "未写入代码主题")

    let existing = """
    [desktop]
    appearanceTheme = "dark" # mode
    appearanceLightCodeThemeId = "codex"
    appearanceLightChromeTheme = { accent = "#000000", ink = "#111111", surface = "#FFFFFF" }
    untouched = 42
    """
    let replaced = try edit(existing, themeID: "notion-paper")
    try expect(occurrences(of: "appearanceTheme =", in: replaced) == 1, "appearanceTheme 重复")
    try expect(occurrences(of: "appearanceLightChromeTheme =", in: replaced) == 1, "Chrome theme 重复")
    try expect(replaced.contains("appearanceTheme = \"light\" # mode"), "未保留行尾注释")
    try expect(replaced.contains("untouched = 42"), "误改无关键")

    let multiline = """
    [desktop]
    before = "kept"
    appearanceDarkChromeTheme = {
      accent = "#111111",
      ink = "#EEEEEE",
      surface = "#222222",
      fonts = { code = "Mono", ui = "UI" }
    } # old theme
    after = "kept too"

    [features]
    memories = true
    """
    let multilineResult = try edit(multiline, themeID: "tokyo-night")
    try expect(occurrences(of: "appearanceDarkChromeTheme =", in: multilineResult) == 1, "多行主题值未完整替换")
    try expect(multilineResult.contains("} # old theme\nafter = \"kept too\""), "多行值注释或后续键损坏")

    let empty = try edit("", themeID: "codex-dark")
    try expect(empty.hasPrefix("[desktop]\n"), "空配置未创建 desktop 段落")

    let nested = """
    [desktop]
    localeOverride = "zh-CN"

    [desktop.workspace]
    width = 320

    [desktop.workspace.pane]
    selected = "console"

    [features]
    memories = true
    """
    let nestedResult = try edit(nested, themeID: "github-light")
    let appearanceIndex = try require(nestedResult.range(of: "appearanceTheme ="), "嵌套段落场景未插入主题键")
    let childIndex = try require(nestedResult.range(of: "[desktop.workspace]"), "嵌套段落丢失")
    try expect(appearanceIndex.lowerBound < childIndex.lowerBound, "主题键错误插入 desktop 子表")

    let sectionTheme = """
    [desktop]
    appearanceTheme = "dark"

    [desktop.appearanceDarkChromeTheme]
    accent = "#111111"
    ink = "#EEEEEE"
    surface = "#222222"

    [desktop.appearanceDarkChromeTheme.fonts]
    code = "Mono"

    [features]
    memories = true
    """
    let sectionResult = try edit(sectionTheme, themeID: "tokyo-night")
    try expect(!sectionResult.contains("[desktop.appearanceDarkChromeTheme]"), "未移除已有 Chrome 子表")
    try expect(occurrences(of: "appearanceDarkChromeTheme =", in: sectionResult) == 1, "Chrome 子表迁移后键数量错误")
    try expect(sectionResult.contains("[features]\nmemories = true"), "Chrome 子表迁移误改后续配置")

    let editor = TOMLDocumentEditor()
    let sectionData = Data(sectionTheme.utf8)
    let baseline = try editor.appearanceBaseline(from: sectionData)
    let appliedSection = try editor.applying(
        theme: require(ThemeCatalog.theme(id: "tokyo-night"), "缺少 Tokyo Night"),
        to: sectionData
    )
    let restoredSection = try editor.restoringAppearance(in: appliedSection, baseline: baseline)
    let restoredSectionText = String(decoding: restoredSection, as: UTF8.self)
    try expect(restoredSectionText.contains("[desktop.appearanceDarkChromeTheme]"), "未恢复原始 Chrome 子表")
    try expect(restoredSectionText.contains("[features]\nmemories = true"), "恢复 Chrome 子表误改后续配置")

    let conflictingTheme = """
    [desktop]
    appearanceDarkChromeTheme = { accent = "#000000" }

    [desktop.appearanceDarkChromeTheme]
    accent = "#111111"
    """
    do {
        _ = try edit(conflictingTheme, themeID: "tokyo-night")
        throw CheckFailure.failed("Chrome 内联值与子表冲突未 fail closed")
    } catch ThemeServiceError.invalidConfiguration {
        // Expected.
    }
}

func checkCatalog() throws {
    try expect(ThemeCatalog.builtIn.count >= 8, "内置主题数量不足")
    let pattern = try NSRegularExpression(pattern: "^#[0-9A-Fa-f]{6}$")
    for theme in ThemeCatalog.builtIn {
        let colors = [
            theme.chromeTheme.accent, theme.chromeTheme.ink, theme.chromeTheme.surface,
            theme.chromeTheme.semanticColors.diffAdded,
            theme.chromeTheme.semanticColors.diffRemoved,
            theme.chromeTheme.semanticColors.skill,
        ]
        for color in colors {
            let range = NSRange(color.startIndex..<color.endIndex, in: color)
            try expect(pattern.firstMatch(in: color, range: range) != nil, "主题 \(theme.id) 颜色无效：\(color)")
        }
        try expect((0...100).contains(theme.chromeTheme.contrast), "主题 \(theme.id) 对比度越界")
    }
}

func checkAppVersion() throws {
    let current = try require(AppVersion("0.2.2"), "当前版本解析失败")
    try expect(try require(AppVersion("v0.3.0"), "v 前缀版本解析失败") > current, "新版本比较失败")
    try expect(try require(AppVersion("0.2.2.0"), "补零版本解析失败") == current, "补零版本应相等")
    try expect(try require(AppVersion("0.2.10"), "多位版本解析失败") > current, "版本比较不应按字符串排序")
    try expect(AppVersion("0.2.beta") == nil, "非法版本未被拒绝")
    try expect(AppVersion("0..2") == nil, "空版本段未被拒绝")
}

func checkCustomTheme() throws {
    var draft = CustomThemeDraft()
    draft.name = "   "
    draft.accent = "not-a-color"
    draft.ink = "#aabbcc"
    draft.contrast = 120
    draft.codeThemeID = "unknown"
    try expect(draft.theme.name == "我的主题", "空自定义主题名称未回退")
    try expect(draft.theme.chromeTheme.accent == "#10A37F", "非法自定义颜色未回退")
    try expect(draft.theme.chromeTheme.ink == "#AABBCC", "自定义颜色未标准化")
    try expect(draft.theme.chromeTheme.contrast == 100, "自定义对比度未限制")
    try expect(draft.theme.codeThemeId == "codex", "非法代码主题未回退")
    try expect(draft.skinSettings == nil, "无图自定义主题不应生成图片设置")

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexSkinCustomChecks-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = CustomThemeStore(supportDirectoryURL: root)
    try store.save(draft)
    try expect(try store.load() == draft, "自定义主题保存后不一致")
    try expect(fileMode(store.draftURL) == 0o600, "自定义主题文件权限不是 0600")

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
        throw CheckFailure.failed("无法生成图片测试夹具")
    }
    let source = root.appendingPathComponent("fixture.png")
    try png.write(to: source)
    let name = try store.importBackground(from: source)
    let imported = try require(store.backgroundURL(named: name), "导入图片不存在")
    try expect(imported.pathExtension == "png", "导入图片未规范化为 PNG")
    try expect(fileMode(imported) == 0o600, "导入图片权限不是 0600")
    draft.backgroundImageName = name
    try expect(draft.skinSettings?.fit == .cover, "图片设置未生成")

    let invalid = root.appendingPathComponent("invalid.png")
    try Data("not an image".utf8).write(to: invalid)
    do {
        _ = try store.importBackground(from: invalid)
        throw CheckFailure.failed("伪造图片未被拒绝")
    } catch ThemeServiceError.invalidBackground {
        // Expected.
    }

    let tinyBitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 100,
        pixelsHigh: 100,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let tinyURL = root.appendingPathComponent("tiny.png")
    try tinyBitmap.representation(using: .png, properties: [:])!.write(to: tinyURL)
    do {
        _ = try store.importBackground(from: tinyURL)
        throw CheckFailure.failed("过小图片未被拒绝")
    } catch ThemeServiceError.invalidBackground {
        // Expected.
    }

    let symlink = store.backgroundDirectoryURL.appendingPathComponent("linked.png")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
    try expect(store.backgroundURL(named: "linked.png") == nil, "背景符号链接未被拒绝")
}

struct Fixture {
    let rootURL: URL
    let configURL: URL
    let store: ConfigurationStore
    let theme: Theme

    init(original: Data? = nil) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexSkinCoreChecks-\(UUID().uuidString)")
        configURL = rootURL.appendingPathComponent("home/.codex/config.toml")
        let support = rootURL.appendingPathComponent("home/Library/Application Support/CodexSkinTool")
        store = ConfigurationStore(paths: ConfigurationPaths(configURL: configURL, supportDirectoryURL: support))
        theme = try require(ThemeCatalog.theme(id: "github-light"), "缺少测试主题")
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let original { try original.write(to: configURL) }
    }

    func cleanup() { try? FileManager.default.removeItem(at: rootURL) }
}

func fileMode(_ url: URL) -> mode_t {
    var info = stat()
    guard stat(url.path, &info) == 0 else { return 0 }
    return info.st_mode & mode_t(0o777)
}

func checkStore() throws {
    let missing = try Fixture()
    defer { missing.cleanup() }
    try missing.store.apply(theme: missing.theme, needsRestart: true)
    try expect(FileManager.default.fileExists(atPath: missing.configURL.path), "未创建配置")
    try expect(!FileManager.default.fileExists(atPath: missing.store.backupURL.path), "不应为空配置创建假备份")
    try expect(missing.store.snapshot().state?.needsRestart == true, "未记录待重启")
    try expect(try missing.store.restore(needsRestart: false), "首次恢复未执行")
    try expect(!FileManager.default.fileExists(atPath: missing.configURL.path), "未恢复为无配置状态")

    let newSettings = try Fixture()
    defer { newSettings.cleanup() }
    try newSettings.store.apply(theme: newSettings.theme, needsRestart: false)
    var generated = try String(contentsOf: newSettings.configURL, encoding: .utf8)
    generated += "\nmodel = \"gpt-5\"\n"
    try Data(generated.utf8).write(to: newSettings.configURL)
    try expect(try newSettings.store.restore(needsRestart: false), "新配置合并恢复未执行")
    let preserved = try String(contentsOf: newSettings.configURL, encoding: .utf8)
    try expect(preserved.contains("model = \"gpt-5\""), "恢复删除了换肤后新增的配置")
    try expect(!preserved.contains("appearanceLightChromeTheme"), "新配置恢复后仍残留工具主题")

    let original = Data("# original\nprovider_secret = \"must-not-be-copied\"\n[desktop]\nlocaleOverride = \"zh-CN\"\n".utf8)
    let repeated = try Fixture(original: original)
    defer { repeated.cleanup() }
    try repeated.store.apply(theme: repeated.theme, needsRestart: false)
    let operationCheckpoint = try repeated.store.checkpoint()
    let checkpointConfig = try Data(contentsOf: repeated.configURL)
    let checkpointState = try Data(contentsOf: repeated.store.stateURL)
    let second = try require(ThemeCatalog.theme(id: "dracula"), "缺少 Dracula 主题")
    try repeated.store.apply(theme: second, needsRestart: true)
    try repeated.store.rollback(to: operationCheckpoint)
    try expect(try Data(contentsOf: repeated.configURL) == checkpointConfig, "操作前配置快照未精确恢复")
    try expect(try Data(contentsOf: repeated.store.stateURL) == checkpointState, "操作前状态快照未精确恢复")
    try repeated.store.apply(theme: second, needsRestart: true)
    try expect(!FileManager.default.fileExists(atPath: repeated.store.backupURL.path), "不应备份整份 Codex 配置")
    let stateData = try Data(contentsOf: repeated.store.stateURL)
    try expect(!String(decoding: stateData, as: UTF8.self).contains("must-not-be-copied"), "状态文件复制了非外观配置")
    var concurrent = try String(contentsOf: repeated.configURL, encoding: .utf8)
    concurrent += "\nnotifications = true\n"
    try Data(concurrent.utf8).write(to: repeated.configURL)
    try expect(try repeated.store.restore(needsRestart: false), "并发配置恢复未执行")
    let merged = try String(contentsOf: repeated.configURL, encoding: .utf8)
    try expect(merged.contains("notifications = true"), "恢复覆盖了换肤后的其他设置：\(merged.debugDescription)")
    try expect(!merged.contains("appearanceLightChromeTheme"), "恢复后仍残留工具主题")

    let crlf = Data("# crlf\r\n[desktop]\r\nx = 1\r\n".utf8)
    let recovery = try Fixture(original: crlf)
    defer { recovery.cleanup() }
    try recovery.store.apply(theme: recovery.theme, needsRestart: false)
    let appliedCRLF = try String(contentsOf: recovery.configURL, encoding: .utf8)
    try expect(occurrences(of: "[desktop]", in: appliedCRLF) == 1, "CRLF 配置重复创建 desktop 段")
    try expect(try recovery.store.restore(needsRestart: true), "恢复未执行")
    let recoveredBytes = try Data(contentsOf: recovery.configURL)
    try expect(
        recoveredBytes == crlf,
        "未按原始字节恢复：themed=\(appliedCRLF.debugDescription) restored=\(String(decoding: recoveredBytes, as: UTF8.self).debugDescription)"
    )
    try expect(fileMode(recovery.configURL) == 0o600, "配置权限不是 0600")
    try expect(fileMode(recovery.store.stateURL) == 0o600, "状态权限不是 0600")

    let noBaseline = try Fixture()
    defer { noBaseline.cleanup() }
    try expect(try !noBaseline.store.restore(needsRestart: true), "无基线恢复应为空操作")

    let duplicate = """
    [desktop]
    appearanceTheme = "light"
    appearanceTheme = "dark"
    """
    do {
        _ = try edit(duplicate, themeID: "github-light")
        throw CheckFailure.failed("重复受管键未 fail closed")
    } catch ThemeServiceError.invalidConfiguration {
        // Expected.
    }
}

do {
    try checkEditor()
    try checkCatalog()
    try checkAppVersion()
    try checkCustomTheme()
    try checkStore()
    print("PASS: CodexSkinCoreChecks")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
