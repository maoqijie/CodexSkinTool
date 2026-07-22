use crate::atomic;
use crate::catalog;
use crate::error::{AppError, Result};
use crate::images::ImageStore;
use crate::models::{CustomThemeDraft, Theme};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use uuid::Uuid;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ThemeKind {
    BuiltIn,
    Custom,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ThemeLibraryItem {
    pub id: String,
    pub kind: ThemeKind,
    pub theme: Theme,
    pub custom_draft: Option<CustomThemeDraft>,
    pub background_url: Option<String>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SavedCustomTheme {
    pub id: String,
    pub draft: CustomThemeDraft,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
struct LibraryState {
    version: u8,
    #[serde(alias = "hiddenBuiltInIDs")]
    hidden_built_in_ids: HashSet<String>,
    custom_themes: Vec<SavedCustomTheme>,
}

pub struct ThemeLibrary {
    path: PathBuf,
    images: ImageStore,
}

impl ThemeLibrary {
    pub fn new(support: &Path) -> Self {
        Self {
            path: support.join("theme-library.json"),
            images: ImageStore::new(support),
        }
    }

    pub fn items(&self) -> Result<Vec<ThemeLibraryItem>> {
        let state = self.load()?;
        let mut items = Vec::new();
        for theme in catalog::built_in_themes() {
            if !state.hidden_built_in_ids.contains(&theme.id) {
                items.push(ThemeLibraryItem {
                    id: theme.id.clone(),
                    kind: ThemeKind::BuiltIn,
                    theme,
                    custom_draft: None,
                    background_url: None,
                });
            }
        }
        for saved in state.custom_themes {
            items.push(ThemeLibraryItem {
                id: saved.id.clone(),
                kind: ThemeKind::Custom,
                theme: saved.draft.to_theme(&saved.id),
                background_url: self
                    .images
                    .data_url(saved.draft.background_image_name.as_deref())?,
                custom_draft: Some(saved.draft),
            });
        }
        Ok(items)
    }

    pub fn save_custom(&self, draft: &CustomThemeDraft) -> Result<()> {
        let mut state = self.load()?;
        let mut saved_draft = draft.normalized();
        saved_draft.background_image_name =
            self.images.copy(draft.background_image_name.as_deref())?;
        state.custom_themes.push(SavedCustomTheme {
            id: format!("user-{}", Uuid::new_v4()),
            draft: saved_draft.clone(),
        });
        if let Err(error) = self.write(&state) {
            let _ = self
                .images
                .remove(saved_draft.background_image_name.as_deref());
            return Err(error);
        }
        Ok(())
    }

    pub fn delete(&self, id: &str) -> Result<()> {
        let mut state = self.load()?;
        if catalog::theme_by_id(id).is_some() {
            state.hidden_built_in_ids.insert(id.into());
            return self.write(&state);
        }
        let Some(index) = state.custom_themes.iter().position(|item| item.id == id) else {
            return Ok(());
        };
        let removed = state.custom_themes.remove(index);
        self.write(&state)?;
        self.images
            .remove(removed.draft.background_image_name.as_deref())
    }

    pub fn rename(&self, id: &str, name: &str) -> Result<()> {
        let normalized = name.trim();
        if normalized.is_empty()
            || normalized.chars().count() > 40
            || normalized.chars().any(char::is_control)
        {
            return Err(AppError::InvalidInput(
                "主题名称必须为 1 到 40 个非控制字符".into(),
            ));
        }
        let mut state = self.load()?;
        let item = state
            .custom_themes
            .iter_mut()
            .find(|item| item.id == id)
            .ok_or_else(|| AppError::InvalidInput("只能重命名已保存的自定义主题".into()))?;
        item.draft.name = normalized.into();
        self.write(&state)
    }

    pub fn restore_built_ins(&self) -> Result<()> {
        let mut state = self.load()?;
        state.hidden_built_in_ids.clear();
        self.write(&state)
    }

    fn load(&self) -> Result<LibraryState> {
        if !self.path.exists() {
            return Ok(LibraryState {
                version: 1,
                ..LibraryState::default()
            });
        }
        let data = fs::read(&self.path)
            .map_err(|error| AppError::path("读取主题资料库", &self.path, error))?;
        let state: LibraryState = serde_json::from_slice(&data)?;
        let ids: HashSet<_> = state.custom_themes.iter().map(|item| &item.id).collect();
        let images: Vec<_> = state
            .custom_themes
            .iter()
            .filter_map(|item| item.draft.background_image_name.as_deref())
            .collect();
        let valid = state.version == 1
            && ids.len() == state.custom_themes.len()
            && state
                .custom_themes
                .iter()
                .all(|item| item.id.starts_with("user-"))
            && images.iter().collect::<HashSet<_>>().len() == images.len()
            && images
                .iter()
                .all(|name| self.images.resolve(Some(name)).is_some());
        if !valid {
            return Err(AppError::InvalidState("主题资料库格式无效".into()));
        }
        Ok(state)
    }

    fn write(&self, state: &LibraryState) -> Result<()> {
        atomic::write_private(&self.path, &serde_json::to_vec_pretty(state)?)
    }
}
