use crate::error::{AppError, Result};
use std::path::PathBuf;

#[derive(Clone, Debug)]
pub struct AppPaths {
    pub config: PathBuf,
    pub support: PathBuf,
}

impl AppPaths {
    pub fn live() -> Result<Self> {
        let home =
            dirs::home_dir().ok_or_else(|| AppError::InvalidState("无法确定用户主目录".into()))?;
        let support = dirs::data_local_dir()
            .or_else(dirs::data_dir)
            .ok_or_else(|| AppError::InvalidState("无法确定应用数据目录".into()))?
            .join("CodexSkinTool");
        Ok(Self {
            config: home.join(".codex").join("config.toml"),
            support,
        })
    }

    #[cfg(test)]
    pub fn isolated(root: &std::path::Path) -> Self {
        Self {
            config: root.join("home").join(".codex").join("config.toml"),
            support: root.join("support"),
        }
    }
}
