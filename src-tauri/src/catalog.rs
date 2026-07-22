use crate::models::{
    platform_fonts, ChromeTheme, Theme, ThemeMode, ThemeSemanticColors, SUPPORTED_CODE_THEMES,
};

struct Definition {
    id: &'static str,
    name: &'static str,
    description: &'static str,
    mode: ThemeMode,
    code: &'static str,
    accent: &'static str,
    ink: &'static str,
    surface: &'static str,
    contrast: i32,
    added: &'static str,
    removed: &'static str,
    skill: &'static str,
}

const DEFINITIONS: &[Definition] = &[
    Definition {
        id: "codex-light",
        name: "Codex 明亮",
        description: "干净克制的 Codex 原生明亮风格",
        mode: ThemeMode::Light,
        code: "codex",
        accent: "#0D7C66",
        ink: "#17211F",
        surface: "#F7FAF9",
        contrast: 45,
        added: "#16835D",
        removed: "#D13C3C",
        skill: "#7A5AF8",
    },
    Definition {
        id: "github-light",
        name: "GitHub 明亮",
        description: "清晰中性的开发者工作台",
        mode: ThemeMode::Light,
        code: "github",
        accent: "#0969DA",
        ink: "#24292F",
        surface: "#FFFFFF",
        contrast: 42,
        added: "#1A7F37",
        removed: "#CF222E",
        skill: "#8250DF",
    },
    Definition {
        id: "notion-paper",
        name: "Notion 纸白",
        description: "温和低对比的专注写作体验",
        mode: ThemeMode::Light,
        code: "notion",
        accent: "#2383E2",
        ink: "#37352F",
        surface: "#FFFFFF",
        contrast: 34,
        added: "#0F7B6C",
        removed: "#D44C47",
        skill: "#9065B0",
    },
    Definition {
        id: "solarized-light",
        name: "Solarized 明亮",
        description: "经典护眼配色与稳定层次",
        mode: ThemeMode::Light,
        code: "solarized",
        accent: "#268BD2",
        ink: "#586E75",
        surface: "#FDF6E3",
        contrast: 38,
        added: "#2AA198",
        removed: "#DC322F",
        skill: "#6C71C4",
    },
    Definition {
        id: "codex-dark",
        name: "Codex 深色",
        description: "Codex 原生质感的沉静深色界面",
        mode: ThemeMode::Dark,
        code: "codex",
        accent: "#10A37F",
        ink: "#ECECF1",
        surface: "#171717",
        contrast: 55,
        added: "#32B47A",
        removed: "#FF5C5C",
        skill: "#B58AF5",
    },
    Definition {
        id: "tokyo-night",
        name: "Tokyo Night",
        description: "冷静夜色与鲜明代码焦点",
        mode: ThemeMode::Dark,
        code: "tokyo-night",
        accent: "#7AA2F7",
        ink: "#C0CAF5",
        surface: "#1A1B26",
        contrast: 60,
        added: "#9ECE6A",
        removed: "#F7768E",
        skill: "#BB9AF7",
    },
    Definition {
        id: "rose-pine",
        name: "Rose Pine",
        description: "柔和玫瑰色调的低眩光深色主题",
        mode: ThemeMode::Dark,
        code: "rose-pine",
        accent: "#C4A7E7",
        ink: "#E0DEF4",
        surface: "#191724",
        contrast: 48,
        added: "#9CCFD8",
        removed: "#EB6F92",
        skill: "#F6C177",
    },
    Definition {
        id: "dracula",
        name: "Dracula",
        description: "高辨识度的经典深色开发主题",
        mode: ThemeMode::Dark,
        code: "dracula",
        accent: "#BD93F9",
        ink: "#F8F8F2",
        surface: "#282A36",
        contrast: 62,
        added: "#50FA7B",
        removed: "#FF5555",
        skill: "#FF79C6",
    },
    Definition {
        id: "everforest",
        name: "Everforest",
        description: "自然绿色调的舒缓深色主题",
        mode: ThemeMode::Dark,
        code: "everforest",
        accent: "#A7C080",
        ink: "#D3C6AA",
        surface: "#2D353B",
        contrast: 46,
        added: "#83C092",
        removed: "#E67E80",
        skill: "#D699B6",
    },
    Definition {
        id: "vercel-dark",
        name: "Vercel 黑",
        description: "高对比黑白界面与利落蓝色强调",
        mode: ThemeMode::Dark,
        code: "vercel",
        accent: "#006EFE",
        ink: "#EDEDED",
        surface: "#000000",
        contrast: 68,
        added: "#00AD3A",
        removed: "#F13342",
        skill: "#9540D5",
    },
];

pub fn built_in_themes() -> Vec<Theme> {
    DEFINITIONS.iter().map(to_theme).collect()
}

pub fn theme_by_id(id: &str) -> Option<Theme> {
    DEFINITIONS.iter().find(|item| item.id == id).map(to_theme)
}

pub fn supported_ids() -> Vec<String> {
    SUPPORTED_CODE_THEMES
        .iter()
        .map(ToString::to_string)
        .collect()
}

fn to_theme(value: &Definition) -> Theme {
    Theme {
        id: value.id.into(),
        name: value.name.into(),
        description: value.description.into(),
        mode: value.mode,
        code_theme_id: value.code.into(),
        chrome_theme: ChromeTheme {
            accent: value.accent.into(),
            ink: value.ink.into(),
            surface: value.surface.into(),
            contrast: value.contrast,
            fonts: platform_fonts(),
            opaque_windows: true,
            semantic_colors: ThemeSemanticColors {
                diff_added: value.added.into(),
                diff_removed: value.removed.into(),
                skill: value.skill.into(),
            },
        },
    }
}
