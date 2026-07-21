import Darwin
import Foundation
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

    let original = Data("# original\n[desktop]\nlocaleOverride = \"zh-CN\"\n".utf8)
    let repeated = try Fixture(original: original)
    defer { repeated.cleanup() }
    try repeated.store.apply(theme: repeated.theme, needsRestart: false)
    let second = try require(ThemeCatalog.theme(id: "dracula"), "缺少 Dracula 主题")
    try repeated.store.apply(theme: second, needsRestart: true)
    try expect(try Data(contentsOf: repeated.store.backupURL) == original, "重复应用覆盖了原始备份")
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
    try expect(try recovery.store.restore(needsRestart: true), "恢复未执行")
    let recoveredBytes = try Data(contentsOf: recovery.configURL)
    try expect(recoveredBytes == crlf, "未按原始字节恢复：\(String(decoding: recoveredBytes, as: UTF8.self).debugDescription)")
    try expect(fileMode(recovery.configURL) == 0o600, "配置权限不是 0600")
    try expect(fileMode(recovery.store.backupURL) == 0o600, "备份权限不是 0600")

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
    try checkStore()
    print("PASS: CodexSkinCoreChecks")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
