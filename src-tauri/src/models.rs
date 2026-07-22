use serde::{Deserialize, Serialize};

pub const SUPPORTED_CODE_THEMES: &[&str] = &[
    "codex",
    "github",
    "notion",
    "solarized",
    "tokyo-night",
    "rose-pine",
    "dracula",
    "everforest",
    "vercel",
];

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ThemeMode {
    Light,
    #[default]
    Dark,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ThemeFonts {
    pub code: Option<String>,
    pub ui: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ThemeSemanticColors {
    pub diff_added: String,
    pub diff_removed: String,
    pub skill: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChromeTheme {
    pub accent: String,
    pub ink: String,
    pub surface: String,
    pub contrast: i32,
    pub fonts: ThemeFonts,
    pub opaque_windows: bool,
    pub semantic_colors: ThemeSemanticColors,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Theme {
    pub id: String,
    pub name: String,
    pub description: String,
    pub mode: ThemeMode,
    pub code_theme_id: String,
    pub chrome_theme: ChromeTheme,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum BackgroundFit {
    #[default]
    Cover,
    Contain,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub struct CustomThemeDraft {
    pub name: String,
    pub mode: ThemeMode,
    #[serde(alias = "codeThemeID")]
    pub code_theme_id: String,
    pub accent: String,
    pub ink: String,
    pub surface: String,
    pub contrast: i32,
    pub background_image_name: Option<String>,
    pub background_opacity: f64,
    pub background_blur: f64,
    pub background_fit: BackgroundFit,
    pub background_brightness: f64,
    pub background_focus_x: f64,
    pub background_focus_y: f64,
}

impl Default for CustomThemeDraft {
    fn default() -> Self {
        Self {
            name: "我的主题".into(),
            mode: ThemeMode::Dark,
            code_theme_id: "codex".into(),
            accent: "#10A37F".into(),
            ink: "#F4F4F4".into(),
            surface: "#171717".into(),
            contrast: 55,
            background_image_name: None,
            background_opacity: 0.28,
            background_blur: 0.0,
            background_fit: BackgroundFit::Cover,
            background_brightness: 1.0,
            background_focus_x: 0.5,
            background_focus_y: 0.5,
        }
    }
}

impl CustomThemeDraft {
    pub fn normalized(&self) -> Self {
        let fallback_ink = if self.mode == ThemeMode::Dark {
            "#F4F4F4"
        } else {
            "#202020"
        };
        let fallback_surface = if self.mode == ThemeMode::Dark {
            "#171717"
        } else {
            "#FFFFFF"
        };
        Self {
            name: normalize_name(&self.name),
            mode: self.mode,
            code_theme_id: if SUPPORTED_CODE_THEMES.contains(&self.code_theme_id.as_str()) {
                self.code_theme_id.clone()
            } else {
                "codex".into()
            },
            accent: normalize_color(&self.accent, "#10A37F"),
            ink: normalize_color(&self.ink, fallback_ink),
            surface: normalize_color(&self.surface, fallback_surface),
            contrast: self.contrast.clamp(0, 100),
            background_image_name: self.background_image_name.clone(),
            background_opacity: finite_clamp(self.background_opacity, 0.08, 0.85, 0.28),
            background_blur: finite_clamp(self.background_blur, 0.0, 24.0, 0.0),
            background_fit: self.background_fit,
            background_brightness: finite_clamp(self.background_brightness, 0.45, 1.25, 1.0),
            background_focus_x: finite_clamp(self.background_focus_x, 0.0, 1.0, 0.5),
            background_focus_y: finite_clamp(self.background_focus_y, 0.0, 1.0, 0.5),
        }
    }

    pub fn to_theme(&self, id: impl Into<String>) -> Theme {
        let value = self.normalized();
        Theme {
            id: id.into(),
            name: value.name,
            description: if value.background_image_name.is_some() {
                "自定义配色与本地图片背景".into()
            } else {
                "自定义配色与代码主题".into()
            },
            mode: value.mode,
            code_theme_id: value.code_theme_id,
            chrome_theme: ChromeTheme {
                accent: value.accent.clone(),
                ink: value.ink,
                surface: value.surface,
                contrast: value.contrast,
                fonts: platform_fonts(),
                opaque_windows: true,
                semantic_colors: ThemeSemanticColors {
                    diff_added: "#32B47A".into(),
                    diff_removed: "#E5484D".into(),
                    skill: value.accent,
                },
            },
        }
    }
}

fn normalize_name(value: &str) -> String {
    let name = value.trim();
    if name.is_empty() {
        "我的主题".into()
    } else {
        name.chars().take(40).collect()
    }
}

fn normalize_color(value: &str, fallback: &str) -> String {
    let bytes = value.as_bytes();
    if bytes.len() == 7 && bytes[0] == b'#' && bytes[1..].iter().all(u8::is_ascii_hexdigit) {
        value.to_ascii_uppercase()
    } else {
        fallback.into()
    }
}

fn finite_clamp(value: f64, minimum: f64, maximum: f64, fallback: f64) -> f64 {
    if value.is_finite() {
        value.clamp(minimum, maximum)
    } else {
        fallback
    }
}

pub fn platform_fonts() -> ThemeFonts {
    ThemeFonts {
        code: Some("\"SFMono-Regular\", Menlo, Consolas, monospace".into()),
        ui: Some("-apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif".into()),
    }
}
