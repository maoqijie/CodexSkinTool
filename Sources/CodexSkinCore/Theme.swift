import Foundation

public enum ThemeMode: String, Codable, CaseIterable, Sendable {
    case light
    case dark
}

public struct ThemeFonts: Codable, Equatable, Sendable {
    public let code: String?
    public let ui: String?

    public init(code: String?, ui: String?) {
        self.code = code
        self.ui = ui
    }
}

public struct ThemeSemanticColors: Codable, Equatable, Sendable {
    public let diffAdded: String
    public let diffRemoved: String
    public let skill: String

    public init(diffAdded: String, diffRemoved: String, skill: String) {
        self.diffAdded = diffAdded
        self.diffRemoved = diffRemoved
        self.skill = skill
    }
}

public struct ChromeTheme: Codable, Equatable, Sendable {
    public let accent: String
    public let ink: String
    public let surface: String
    public let contrast: Int
    public let fonts: ThemeFonts
    public let opaqueWindows: Bool
    public let semanticColors: ThemeSemanticColors

    public init(
        accent: String,
        ink: String,
        surface: String,
        contrast: Int,
        fonts: ThemeFonts,
        opaqueWindows: Bool,
        semanticColors: ThemeSemanticColors
    ) {
        self.accent = accent
        self.ink = ink
        self.surface = surface
        self.contrast = contrast
        self.fonts = fonts
        self.opaqueWindows = opaqueWindows
        self.semanticColors = semanticColors
    }
}

public struct Theme: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let mode: ThemeMode
    public let codeThemeId: String
    public let chromeTheme: ChromeTheme

    public init(
        id: String,
        name: String,
        description: String,
        mode: ThemeMode,
        codeThemeId: String,
        chromeTheme: ChromeTheme
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.mode = mode
        self.codeThemeId = codeThemeId
        self.chromeTheme = chromeTheme
    }

    public var subtitle: String { description }
    public var isDark: Bool { mode == .dark }
    public var chrome: ChromeTheme { chromeTheme }
    public var previewColors: [String] {
        [chromeTheme.accent, chromeTheme.surface, chromeTheme.ink]
    }
}

public typealias SkinTheme = Theme

public enum ThemeCatalog {
    public static let builtIn: [Theme] = [
        theme("codex-light", "Codex 明亮", "干净克制的 Codex 原生明亮风格", .light, "codex",
              "#0D7C66", "#17211F", "#F7FAF9", 45, "#16835D", "#D13C3C", "#7A5AF8"),
        theme("github-light", "GitHub 明亮", "清晰中性的开发者工作台", .light, "github",
              "#0969DA", "#24292F", "#FFFFFF", 42, "#1A7F37", "#CF222E", "#8250DF"),
        theme("notion-paper", "Notion 纸白", "温和低对比的专注写作体验", .light, "notion",
              "#2383E2", "#37352F", "#FFFFFF", 34, "#0F7B6C", "#D44C47", "#9065B0"),
        theme("solarized-light", "Solarized 明亮", "经典护眼配色与稳定层次", .light, "solarized",
              "#268BD2", "#586E75", "#FDF6E3", 38, "#2AA198", "#DC322F", "#6C71C4"),
        theme("codex-dark", "Codex 深色", "Codex 原生质感的沉静深色界面", .dark, "codex",
              "#10A37F", "#ECECF1", "#171717", 55, "#32B47A", "#FF5C5C", "#B58AF5"),
        theme("tokyo-night", "Tokyo Night", "冷静夜色与鲜明代码焦点", .dark, "tokyo-night",
              "#7AA2F7", "#C0CAF5", "#1A1B26", 60, "#9ECE6A", "#F7768E", "#BB9AF7"),
        theme("rose-pine", "Rose Pine", "柔和玫瑰色调的低眩光深色主题", .dark, "rose-pine",
              "#C4A7E7", "#E0DEF4", "#191724", 48, "#9CCFD8", "#EB6F92", "#F6C177"),
        theme("dracula", "Dracula", "高辨识度的经典深色开发主题", .dark, "dracula",
              "#BD93F9", "#F8F8F2", "#282A36", 62, "#50FA7B", "#FF5555", "#FF79C6"),
        theme("everforest", "Everforest", "自然绿色调的舒缓深色主题", .dark, "everforest",
              "#A7C080", "#D3C6AA", "#2D353B", 46, "#83C092", "#E67E80", "#D699B6"),
        theme("vercel-dark", "Vercel 黑", "高对比黑白界面与利落蓝色强调", .dark, "vercel",
              "#006EFE", "#EDEDED", "#000000", 68, "#00AD3A", "#F13342", "#9540D5")
    ]

    public static func theme(id: String) -> Theme? {
        builtIn.first { $0.id == id }
    }

    private static func theme(
        _ id: String,
        _ name: String,
        _ description: String,
        _ mode: ThemeMode,
        _ codeThemeId: String,
        _ accent: String,
        _ ink: String,
        _ surface: String,
        _ contrast: Int,
        _ added: String,
        _ removed: String,
        _ skill: String
    ) -> Theme {
        Theme(
            id: id,
            name: name,
            description: description,
            mode: mode,
            codeThemeId: codeThemeId,
            chromeTheme: ChromeTheme(
                accent: accent,
                ink: ink,
                surface: surface,
                contrast: contrast,
                fonts: ThemeFonts(
                    code: "\"SFMono-Regular\", Menlo, monospace",
                    ui: "-apple-system, BlinkMacSystemFont, sans-serif"
                ),
                opaqueWindows: true,
                semanticColors: ThemeSemanticColors(
                    diffAdded: added,
                    diffRemoved: removed,
                    skill: skill
                )
            )
        )
    }
}
