use crate::atomic;
use crate::background::BackgroundSession;
use crate::catalog;
use crate::config::{config_exists, ConfigCheckpoint, ConfigStore};
use crate::error::{AppError, Result};
use crate::images::ImageStore;
use crate::library::{ThemeLibrary, ThemeLibraryItem};
use crate::models::{BackgroundSkinStatus, CustomThemeDraft, Theme};
use crate::paths::AppPaths;
use crate::platform::{AppStatus, PlatformService};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

const REPOSITORY_URL: &str = "https://github.com/maoqijie/CodexSkinTool";

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
        let resolved = self.resolve_theme(request)?;
        let before = PlatformService::status();
        let config = self.config();
        let background = self.background();
        let previous_background = background.transaction_draft()?;
        let checkpoint = config.checkpoint()?;
        if let Err(error) = config.apply(&resolved.theme, &resolved.selected_id, before.is_running)
        {
            config.rollback(checkpoint).map_err(|rollback| {
                AppError::InvalidState(format!(
                    "主题写入失败（{error}），且无法回滚本次变更（{rollback}）"
                ))
            })?;
            return Err(error);
        }
        let apply_result = if let Some(draft) = &resolved.background {
            background
                .start(draft)
                .map(|_| "图片主题已应用，Codex 已安全启动".to_string())
        } else {
            background.stop().and_then(|stopped| {
                if before.is_running || stopped {
                    PlatformService::restart()?;
                    Ok("主题已应用，Codex 已安全重启".to_string())
                } else {
                    Ok("主题已应用；下次启动 Codex 时生效".to_string())
                }
            })
        };
        let message = match apply_result.and_then(|message| {
            config.mark_restarted()?;
            Ok(message)
        }) {
            Ok(message) => message,
            Err(error) => {
                return Err(recover_failed_switch(
                    &config,
                    checkpoint,
                    &background,
                    previous_background,
                    before.is_running,
                    error,
                    "Codex 主题切换失败",
                ));
            }
        };
        Ok(OperationResult {
            status: self.status()?,
            message,
        })
    }

    pub fn restore(&self) -> Result<OperationResult> {
        let before = PlatformService::status();
        let background = self.background();
        let previous_background = background.transaction_draft()?;
        let config = self.config();
        let checkpoint = config.checkpoint()?;
        let result = (|| {
            let stopped_background = background.stop()?;
            let changed = config.restore(before.is_running || stopped_background)?;
            let message = if before.is_running || stopped_background {
                PlatformService::restart()?;
                config.mark_restarted()?;
                if changed {
                    "原始外观已恢复，Codex 已安全重启"
                } else {
                    "图片背景已停止，Codex 已安全重启"
                }
            } else if !changed {
                "没有可恢复的外观基线"
            } else {
                "原始外观已恢复"
            };
            Ok(message)
        })();
        let message = match result {
            Ok(message) => message,
            Err(error) => {
                return Err(recover_failed_switch(
                    &config,
                    checkpoint,
                    &background,
                    previous_background,
                    before.is_running,
                    error,
                    "恢复原始外观失败",
                ));
            }
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
            background_skin: self.background().status(),
        })
    }

    fn resolve_theme(&self, request: ApplyRequest) -> Result<ResolvedTheme> {
        match (request.item_id, request.draft) {
            (Some(id), None) => {
                if let Some(theme) = catalog::theme_by_id(&id) {
                    return Ok(ResolvedTheme {
                        theme,
                        selected_id: id,
                        background: None,
                    });
                }
                let item = self
                    .library()
                    .items()?
                    .into_iter()
                    .find(|item| item.id == id)
                    .ok_or_else(|| AppError::InvalidInput(format!("找不到主题：{id}")))?;
                let background = item
                    .custom_draft
                    .filter(|draft| draft.background_image_name.is_some());
                if let Some(draft) = &background {
                    self.validate_background(draft)?;
                }
                Ok(ResolvedTheme {
                    theme: item.theme,
                    selected_id: item.id,
                    background,
                })
            }
            (None, Some(draft)) => {
                self.validate_background(&draft)?;
                Ok(ResolvedTheme {
                    theme: draft.to_theme("custom"),
                    selected_id: "custom".into(),
                    background: draft.background_image_name.is_some().then_some(draft),
                })
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
    fn background(&self) -> BackgroundSession {
        BackgroundSession::new(self.paths.clone())
    }

    #[cfg(test)]
    pub(crate) fn resolves_background_for_test(&self, request: ApplyRequest) -> Result<bool> {
        Ok(self.resolve_theme(request)?.background.is_some())
    }
}

struct ResolvedTheme {
    theme: Theme,
    selected_id: String,
    background: Option<CustomThemeDraft>,
}

fn restore_background(
    background: &BackgroundSession,
    previous: Option<CustomThemeDraft>,
    was_running: bool,
) -> Result<()> {
    match previous {
        Some(draft) => background.start(&draft),
        None => {
            background.stop()?;
            if was_running {
                PlatformService::restart()?;
            }
            Ok(())
        }
    }
}

fn recover_failed_switch(
    config: &ConfigStore,
    checkpoint: ConfigCheckpoint,
    background: &BackgroundSession,
    previous: Option<CustomThemeDraft>,
    was_running: bool,
    error: AppError,
    context: &str,
) -> AppError {
    let rollback = config.rollback(checkpoint).err();
    let restore = restore_background(background, previous, was_running).err();
    if rollback.is_none() && restore.is_none() {
        return error;
    }
    AppError::InvalidState(format!(
        "{context}（{error}）；配置回滚：{}；运行态恢复：{}",
        rollback.map_or_else(|| "成功".into(), |value| value.to_string()),
        restore.map_or_else(|| "成功".into(), |value| value.to_string())
    ))
}
