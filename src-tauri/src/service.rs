use crate::atomic;
use crate::catalog;
use crate::config::{config_exists, ConfigStore};
use crate::error::{AppError, Result};
use crate::images::ImageStore;
use crate::library::{ThemeLibrary, ThemeLibraryItem};
use crate::models::{CustomThemeDraft, Theme};
use crate::paths::AppPaths;
use crate::platform::{AppStatus, PlatformService};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

const REPOSITORY_URL: &str = "https://github.com/maoqijie/CodexSkinTool";

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackgroundSkinStatus {
    active: bool,
    port: Option<u16>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServiceStatus {
    selected_theme_id: Option<String>,
    config_exists: bool,
    can_restore: bool,
    needs_restart: bool,
    app: AppStatus,
    background_skin: BackgroundSkinStatus,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BootstrapData {
    status: ServiceStatus,
    themes: Vec<ThemeLibraryItem>,
    pub(crate) custom_draft: CustomThemeDraft,
    custom_background_url: Option<String>,
    version: &'static str,
    repository_url: &'static str,
    supported_code_theme_ids: Vec<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ApplyRequest {
    pub item_id: Option<String>,
    pub draft: Option<CustomThemeDraft>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OperationResult {
    status: ServiceStatus,
    message: String,
}

pub struct AppService {
    paths: AppPaths,
}

impl AppService {
    pub fn live() -> Result<Self> {
        Ok(Self {
            paths: AppPaths::live()?,
        })
    }

    #[cfg(test)]
    pub fn isolated(root: &Path) -> Self {
        Self {
            paths: AppPaths::isolated(root),
        }
    }

    pub fn bootstrap(&self) -> Result<BootstrapData> {
        let draft = self.load_draft()?;
        let images = self.images();
        Ok(BootstrapData {
            status: self.status()?,
            themes: self.library().items()?,
            custom_background_url: images.data_url(draft.background_image_name.as_deref())?,
            custom_draft: draft,
            version: env!("CARGO_PKG_VERSION"),
            repository_url: REPOSITORY_URL,
            supported_code_theme_ids: catalog::supported_ids(),
        })
    }

    pub fn apply(&self, request: ApplyRequest) -> Result<OperationResult> {
        let (theme, selected_id) = self.resolve_theme(request)?;
        let before = PlatformService::status();
        let config = self.config();
        let checkpoint = config.checkpoint()?;
        if let Err(error) = config.apply(&theme, &selected_id, before.is_running) {
            config.rollback(checkpoint).map_err(|rollback| {
                AppError::InvalidState(format!(
                    "主题写入失败（{error}），且无法回滚本次变更（{rollback}）"
                ))
            })?;
            return Err(error);
        }
        let message = if before.is_running {
            if let Err(error) = PlatformService::restart() {
                config.rollback(checkpoint).map_err(|rollback| {
                    AppError::InvalidState(format!(
                        "Codex 重启失败（{error}），且无法回滚本次主题变更（{rollback}）"
                    ))
                })?;
                return Err(error);
            }
            config.mark_restarted()?;
            "主题已应用，Codex 已安全重启"
        } else {
            "主题已应用；下次启动 Codex 时生效"
        };
        Ok(OperationResult {
            status: self.status()?,
            message: message.into(),
        })
    }

    pub fn restore(&self) -> Result<OperationResult> {
        let before = PlatformService::status();
        let changed = self.config().restore(before.is_running)?;
        let message = if !changed {
            "没有可恢复的外观基线"
        } else if before.is_running {
            PlatformService::restart()?;
            self.config().mark_restarted()?;
            "原始外观已恢复，Codex 已安全重启"
        } else {
            "原始外观已恢复"
        };
        Ok(OperationResult {
            status: self.status()?,
            message: message.into(),
        })
    }

    pub fn save_draft(&self, draft: CustomThemeDraft) -> Result<BootstrapData> {
        self.validate_background(&draft)?;
        self.write_draft(&draft.normalized())?;
        self.bootstrap()
    }

    pub fn save_to_library(&self, draft: CustomThemeDraft) -> Result<BootstrapData> {
        self.validate_background(&draft)?;
        self.library().save_custom(&draft)?;
        self.bootstrap()
    }

    pub fn delete_theme(&self, id: &str) -> Result<BootstrapData> {
        self.library().delete(id)?;
        self.bootstrap()
    }

    pub fn rename_theme(&self, id: &str, name: &str) -> Result<BootstrapData> {
        self.library().rename(id, name)?;
        self.bootstrap()
    }

    pub fn restore_built_ins(&self) -> Result<BootstrapData> {
        self.library().restore_built_ins()?;
        self.bootstrap()
    }

    pub fn import_background(
        &self,
        path: &Path,
        mut draft: CustomThemeDraft,
    ) -> Result<BootstrapData> {
        let previous = draft.background_image_name.clone();
        let imported = self.images().import(path)?;
        draft.background_image_name = Some(imported.name.clone());
        if let Some(accent) = imported.suggested_accent {
            draft.accent = accent;
        }
        if let Err(error) = self.write_draft(&draft.normalized()) {
            let _ = self.images().remove(Some(&imported.name));
            return Err(error);
        }
        if previous.as_deref() != Some(&imported.name) {
            self.images().remove(previous.as_deref())?;
        }
        self.bootstrap()
    }

    pub fn remove_background(&self, mut draft: CustomThemeDraft) -> Result<BootstrapData> {
        let previous = draft.background_image_name.take();
        self.write_draft(&draft.normalized())?;
        self.images().remove(previous.as_deref())?;
        self.bootstrap()
    }

    fn status(&self) -> Result<ServiceStatus> {
        let state = self.config().read_state()?;
        Ok(ServiceStatus {
            selected_theme_id: state
                .as_ref()
                .and_then(|value| value.selected_theme_id.clone()),
            config_exists: config_exists(&self.paths.config),
            can_restore: state.is_some(),
            needs_restart: state.as_ref().is_some_and(|value| value.needs_restart),
            app: PlatformService::status(),
            background_skin: BackgroundSkinStatus {
                active: false,
                port: None,
            },
        })
    }

    fn resolve_theme(&self, request: ApplyRequest) -> Result<(Theme, String)> {
        match (request.item_id, request.draft) {
            (Some(id), None) => {
                if let Some(theme) = catalog::theme_by_id(&id) {
                    return Ok((theme, id));
                }
                let item = self
                    .library()
                    .items()?
                    .into_iter()
                    .find(|item| item.id == id)
                    .ok_or_else(|| AppError::InvalidInput(format!("找不到主题：{id}")))?;
                if item
                    .custom_draft
                    .as_ref()
                    .is_some_and(|draft| draft.background_image_name.is_some())
                {
                    return Err(AppError::BackgroundUnsupported(
                        "安全的跨平台 CDP 进程身份验证尚未完成".into(),
                    ));
                }
                Ok((item.theme, item.id))
            }
            (None, Some(draft)) => {
                self.validate_background(&draft)?;
                if draft.background_image_name.is_some() {
                    return Err(AppError::BackgroundUnsupported(
                        "安全的跨平台 CDP 进程身份验证尚未完成".into(),
                    ));
                }
                Ok((draft.to_theme("custom"), "custom".into()))
            }
            _ => Err(AppError::InvalidInput(
                "必须且只能指定 itemId 或 draft".into(),
            )),
        }
    }

    fn validate_background(&self, draft: &CustomThemeDraft) -> Result<()> {
        if draft.background_image_name.is_some()
            && self
                .images()
                .resolve(draft.background_image_name.as_deref())
                .is_none()
        {
            return Err(AppError::InvalidImage("已选择的背景图片不存在".into()));
        }
        Ok(())
    }

    fn draft_path(&self) -> PathBuf {
        self.paths.support.join("custom-theme.json")
    }

    fn load_draft(&self) -> Result<CustomThemeDraft> {
        let path = self.draft_path();
        if !path.exists() {
            return Ok(CustomThemeDraft::default());
        }
        let data =
            fs::read(&path).map_err(|error| AppError::path("读取自定义主题", &path, error))?;
        let draft: CustomThemeDraft = serde_json::from_slice(&data)?;
        self.validate_background(&draft)?;
        Ok(draft)
    }

    fn write_draft(&self, draft: &CustomThemeDraft) -> Result<()> {
        atomic::write_private(&self.draft_path(), &serde_json::to_vec_pretty(draft)?)
    }

    fn config(&self) -> ConfigStore {
        ConfigStore::new(self.paths.clone())
    }
    fn library(&self) -> ThemeLibrary {
        ThemeLibrary::new(&self.paths.support)
    }
    fn images(&self) -> ImageStore {
        ImageStore::new(&self.paths.support)
    }
}
