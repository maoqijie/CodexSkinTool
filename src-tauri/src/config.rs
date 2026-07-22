use crate::atomic;
use crate::error::{AppError, Result};
use crate::models::{Theme, ThemeMode};
use crate::paths::AppPaths;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;
use std::str::FromStr;
use toml_edit::{value, DocumentMut, InlineTable, Item, Table, Value};

const MANAGED_KEYS: &[&str] = &[
    "appearanceTheme",
    "appearanceLightCodeThemeId",
    "appearanceDarkCodeThemeId",
    "appearanceLightChromeTheme",
    "appearanceDarkChromeTheme",
];

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppearanceBaseline {
    #[serde(default)]
    pub desktop_existed: bool,
    pub items: BTreeMap<String, Option<String>>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyAppearanceBaseline {
    #[serde(default)]
    values: BTreeMap<String, String>,
    #[serde(default)]
    chrome_sections: BTreeMap<String, String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyPersistedState {
    version: u8,
    original_config_existed: bool,
    original_appearance: Option<LegacyAppearanceBaseline>,
    #[serde(alias = "selectedThemeID")]
    selected_theme_id: Option<String>,
    needs_restart: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PersistedState {
    pub version: u8,
    pub original_config_existed: bool,
    pub baseline: AppearanceBaseline,
    pub selected_theme_id: Option<String>,
    pub needs_restart: bool,
    pub applied_at_unix: Option<u64>,
}

pub struct ConfigStore {
    paths: AppPaths,
}

pub struct ConfigCheckpoint {
    config: Option<Vec<u8>>,
    state: Option<Vec<u8>>,
}

impl ConfigStore {
    pub fn new(paths: AppPaths) -> Self {
        Self { paths }
    }

    pub fn state_path(&self) -> std::path::PathBuf {
        self.paths.support.join("state.json")
    }

    pub fn checkpoint(&self) -> Result<ConfigCheckpoint> {
        Ok(ConfigCheckpoint {
            config: read_optional(&self.paths.config, "读取 Codex 配置 checkpoint")?,
            state: read_optional(&self.state_path(), "读取状态 checkpoint")?,
        })
    }

    pub fn rollback(&self, checkpoint: ConfigCheckpoint) -> Result<()> {
        restore_file(&self.paths.config, checkpoint.config, "回滚 Codex 配置")?;
        restore_file(&self.state_path(), checkpoint.state, "回滚状态")
    }

    pub fn read_state(&self) -> Result<Option<PersistedState>> {
        let path = self.state_path();
        if !path.exists() {
            return Ok(None);
        }
        let data = fs::read(&path).map_err(|error| AppError::path("读取状态", &path, error))?;
        let state = match serde_json::from_slice::<PersistedState>(&data) {
            Ok(state) => state,
            Err(_) => migrate_legacy_state(&data, &self.paths.support)?,
        };
        if state.version != 1
            || state
                .baseline
                .items
                .keys()
                .any(|key| !MANAGED_KEYS.contains(&key.as_str()))
        {
            return Err(AppError::InvalidState("状态版本或受管键无效".into()));
        }
        Ok(Some(state))
    }

    pub fn apply(&self, theme: &Theme, selected_id: &str, needs_restart: bool) -> Result<()> {
        let existed = self.paths.config.exists();
        let source = if existed {
            fs::read_to_string(&self.paths.config)
                .map_err(|error| AppError::path("读取 Codex 配置", &self.paths.config, error))?
        } else {
            String::new()
        };
        let mut document = parse_document(&source)?;
        let existing_state = self.read_state()?;
        let mut state = match existing_state {
            Some(value) => value,
            None => PersistedState {
                version: 1,
                original_config_existed: existed,
                baseline: capture_baseline(&document),
                selected_theme_id: None,
                needs_restart: false,
                applied_at_unix: None,
            },
        };
        if state.selected_theme_id.is_none() && state.applied_at_unix.is_none() {
            self.write_state(&state)?;
        }
        apply_theme(&mut document, theme)?;
        atomic::write_private(&self.paths.config, document.to_string().as_bytes())?;
        state.selected_theme_id = Some(selected_id.into());
        state.needs_restart = needs_restart;
        state.applied_at_unix = Some(unix_time()?);
        self.write_state(&state)
    }

    pub fn restore(&self, needs_restart: bool) -> Result<bool> {
        let Some(mut state) = self.read_state()? else {
            return Ok(false);
        };
        if !self.paths.config.exists() {
            if state.original_config_existed {
                return Err(AppError::InvalidState(
                    "当前 Codex 配置缺失，已停止恢复以避免覆盖外部变更".into(),
                ));
            }
        } else {
            let source = fs::read_to_string(&self.paths.config)
                .map_err(|error| AppError::path("读取 Codex 配置", &self.paths.config, error))?;
            let mut document = parse_document(&source)?;
            restore_baseline(&mut document, &state.baseline)?;
            if effectively_empty(&document) && !state.original_config_existed {
                fs::remove_file(&self.paths.config).map_err(|error| {
                    AppError::path("删除工具创建的配置", &self.paths.config, error)
                })?;
            } else {
                atomic::write_private(&self.paths.config, document.to_string().as_bytes())?;
            }
        }
        state.selected_theme_id = None;
        state.needs_restart = needs_restart;
        state.applied_at_unix = None;
        self.write_state(&state)?;
        Ok(true)
    }

    pub fn mark_restarted(&self) -> Result<()> {
        if let Some(mut state) = self.read_state()? {
            state.needs_restart = false;
            self.write_state(&state)?;
        }
        Ok(())
    }

    fn write_state(&self, state: &PersistedState) -> Result<()> {
        let data = serde_json::to_vec_pretty(state)?;
        atomic::write_private(&self.state_path(), &data)
    }
}

fn migrate_legacy_state(data: &[u8], support: &Path) -> Result<PersistedState> {
    let legacy: LegacyPersistedState = serde_json::from_slice(data)?;
    if legacy.version != 1 && legacy.version != 2 {
        return Err(AppError::InvalidState("无法迁移未知版本的旧状态".into()));
    }
    let baseline = if let Some(appearance) = legacy.original_appearance {
        let items = MANAGED_KEYS
            .iter()
            .map(|key| {
                let snippet = appearance
                    .values
                    .get(*key)
                    .map(|raw| format!("[desktop]\n{key} = {raw}\n"))
                    .or_else(|| appearance.chrome_sections.get(*key).cloned());
                ((*key).to_string(), snippet)
            })
            .collect();
        AppearanceBaseline {
            desktop_existed: true,
            items,
        }
    } else if legacy.original_config_existed {
        let backup_path = support.join("original-config.toml");
        let source = fs::read_to_string(&backup_path)
            .map_err(|error| AppError::path("读取旧版原始配置备份", &backup_path, error))?;
        capture_baseline(&parse_document(&source)?)
    } else {
        capture_baseline(&DocumentMut::new())
    };
    Ok(PersistedState {
        version: 1,
        original_config_existed: legacy.original_config_existed,
        baseline,
        selected_theme_id: legacy.selected_theme_id,
        needs_restart: legacy.needs_restart,
        applied_at_unix: None,
    })
}

fn parse_document(source: &str) -> Result<DocumentMut> {
    DocumentMut::from_str(source).map_err(|error| AppError::InvalidConfig(error.to_string()))
}

fn capture_baseline(document: &DocumentMut) -> AppearanceBaseline {
    let desktop = document.get("desktop").and_then(Item::as_table);
    let items = MANAGED_KEYS
        .iter()
        .map(|key| {
            let snippet = desktop.and_then(|table| table.get(key)).map(|item| {
                let mut root = DocumentMut::new();
                let mut table = Table::new();
                table.insert(key, item.clone());
                root.insert("desktop", Item::Table(table));
                root.to_string()
            });
            ((*key).to_string(), snippet)
        })
        .collect();
    AppearanceBaseline {
        desktop_existed: desktop.is_some(),
        items,
    }
}

fn apply_theme(document: &mut DocumentMut, theme: &Theme) -> Result<()> {
    let desktop = desktop_table(document)?;
    desktop.insert(
        "appearanceTheme",
        value(match theme.mode {
            ThemeMode::Light => "light",
            ThemeMode::Dark => "dark",
        }),
    );
    let prefix = match theme.mode {
        ThemeMode::Light => "appearanceLight",
        ThemeMode::Dark => "appearanceDark",
    };
    desktop.insert(&format!("{prefix}CodeThemeId"), value(&theme.code_theme_id));
    desktop.insert(
        &format!("{prefix}ChromeTheme"),
        Item::Value(Value::InlineTable(chrome_table(theme))),
    );
    Ok(())
}

fn desktop_table(document: &mut DocumentMut) -> Result<&mut Table> {
    if document.get("desktop").is_none() {
        document.insert("desktop", Item::Table(Table::new()));
    }
    document["desktop"]
        .as_table_mut()
        .ok_or_else(|| AppError::InvalidConfig("desktop 必须是 TOML 表".into()))
}

fn chrome_table(theme: &Theme) -> InlineTable {
    let chrome = &theme.chrome_theme;
    let mut fonts = InlineTable::new();
    fonts.insert(
        "code",
        Value::from(chrome.fonts.code.clone().unwrap_or_default()),
    );
    fonts.insert(
        "ui",
        Value::from(chrome.fonts.ui.clone().unwrap_or_default()),
    );
    let mut semantic = InlineTable::new();
    semantic.insert(
        "diffAdded",
        Value::from(chrome.semantic_colors.diff_added.clone()),
    );
    semantic.insert(
        "diffRemoved",
        Value::from(chrome.semantic_colors.diff_removed.clone()),
    );
    semantic.insert("skill", Value::from(chrome.semantic_colors.skill.clone()));
    let mut table = InlineTable::new();
    table.insert("accent", Value::from(chrome.accent.clone()));
    table.insert("ink", Value::from(chrome.ink.clone()));
    table.insert("surface", Value::from(chrome.surface.clone()));
    table.insert("contrast", Value::from(i64::from(chrome.contrast)));
    table.insert("fonts", Value::InlineTable(fonts));
    table.insert("opaqueWindows", Value::from(chrome.opaque_windows));
    table.insert("semanticColors", Value::InlineTable(semantic));
    table
}

fn restore_baseline(document: &mut DocumentMut, baseline: &AppearanceBaseline) -> Result<()> {
    let desktop = desktop_table(document)?;
    for key in MANAGED_KEYS {
        match baseline.items.get(*key).and_then(Option::as_ref) {
            Some(snippet) => {
                let parsed = parse_document(snippet)?;
                let item = parsed["desktop"]
                    .as_table()
                    .and_then(|table| table.get(key))
                    .ok_or_else(|| AppError::InvalidState(format!("基线缺少 {key}")))?
                    .clone();
                desktop.insert(key, item);
            }
            None => {
                desktop.remove(key);
            }
        }
    }
    if !baseline.desktop_existed && desktop.is_empty() {
        document.remove("desktop");
    }
    Ok(())
}

fn effectively_empty(document: &DocumentMut) -> bool {
    document
        .iter()
        .all(|(key, item)| key == "desktop" && item.as_table().is_some_and(Table::is_empty))
}

fn unix_time() -> Result<u64> {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .map_err(|error| AppError::InvalidState(format!("系统时间无效：{error}")))
}

pub fn config_exists(path: &Path) -> bool {
    path.is_file()
}

fn read_optional(path: &Path, context: &str) -> Result<Option<Vec<u8>>> {
    if path.exists() {
        fs::read(path)
            .map(Some)
            .map_err(|error| AppError::path(context, path, error))
    } else {
        Ok(None)
    }
}

fn restore_file(path: &Path, data: Option<Vec<u8>>, context: &str) -> Result<()> {
    if let Some(data) = data {
        atomic::write_private(path, &data)
    } else if path.exists() {
        fs::remove_file(path).map_err(|error| AppError::path(context, path, error))
    } else {
        Ok(())
    }
}
