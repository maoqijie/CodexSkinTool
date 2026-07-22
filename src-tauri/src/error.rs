use std::path::PathBuf;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("{0}")]
    InvalidInput(String),
    #[error("Codex 配置无效：{0}")]
    InvalidConfig(String),
    #[error("本地状态无效：{0}")]
    InvalidState(String),
    #[error("文件操作失败：{context}（{source}）")]
    Io {
        context: String,
        #[source]
        source: std::io::Error,
    },
    #[error("JSON 数据无效：{0}")]
    Json(#[from] serde_json::Error),
    #[error("未找到 Codex Desktop")]
    AppNotInstalled,
    #[error("Codex 操作失败：{0}")]
    AppControl(String),
    #[error("图片背景暂不可用：{0}")]
    BackgroundUnsupported(String),
    #[error("图片无效：{0}")]
    InvalidImage(String),
}

impl AppError {
    pub fn io(context: impl Into<String>, source: std::io::Error) -> Self {
        Self::Io {
            context: context.into(),
            source,
        }
    }

    pub fn path(context: &str, path: &std::path::Path, source: std::io::Error) -> Self {
        Self::io(format!("{context} {}", path.display()), source)
    }
}

impl serde::Serialize for AppError {
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&self.to_string())
    }
}

pub type Result<T> = std::result::Result<T, AppError>;

pub fn invalid_path(path: PathBuf) -> AppError {
    AppError::InvalidInput(format!("路径不是普通文件：{}", path.display()))
}
