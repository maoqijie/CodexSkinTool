use crate::error::{AppError, Result};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use uuid::Uuid;

pub fn write_private(path: &Path, data: &[u8]) -> Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| AppError::InvalidInput("目标文件缺少父目录".into()))?;
    fs::create_dir_all(parent).map_err(|error| AppError::path("创建目录", parent, error))?;
    let temporary = temporary_path(path);
    let result = (|| {
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options
            .open(&temporary)
            .map_err(|error| AppError::path("创建临时文件", &temporary, error))?;
        file.write_all(data)
            .map_err(|error| AppError::path("写入临时文件", &temporary, error))?;
        file.sync_all()
            .map_err(|error| AppError::path("同步临时文件", &temporary, error))?;
        drop(file);
        restrict_to_current_user(&temporary)?;
        replace(&temporary, path)?;
        restrict_to_current_user(path)?;
        sync_parent(parent)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

fn temporary_path(path: &Path) -> PathBuf {
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("data");
    path.with_file_name(format!(".{name}.{}.tmp", Uuid::new_v4()))
}

#[cfg(not(windows))]
fn replace(source: &Path, destination: &Path) -> Result<()> {
    fs::rename(source, destination)
        .map_err(|error| AppError::path("原子替换文件", destination, error))
}

#[cfg(windows)]
fn replace(source: &Path, destination: &Path) -> Result<()> {
    use std::os::windows::ffi::OsStrExt;
    use windows::core::PCWSTR;
    use windows::Win32::Storage::FileSystem::{
        MoveFileExW, ReplaceFileW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH,
        REPLACE_FILE_FLAGS,
    };

    let source_wide: Vec<u16> = source.as_os_str().encode_wide().chain(Some(0)).collect();
    let destination_wide: Vec<u16> = destination
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect();
    let result = unsafe {
        if destination.exists() {
            ReplaceFileW(
                PCWSTR(destination_wide.as_ptr()),
                PCWSTR(source_wide.as_ptr()),
                PCWSTR::null(),
                REPLACE_FILE_FLAGS(0),
                None,
                None,
            )
        } else {
            MoveFileExW(
                PCWSTR(source_wide.as_ptr()),
                PCWSTR(destination_wide.as_ptr()),
                MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
            )
        }
    };
    result.map_err(|error| {
        AppError::io(
            format!("原子替换文件 {}", destination.display()),
            error.into(),
        )
    })
}

#[cfg(unix)]
fn sync_parent(parent: &Path) -> Result<()> {
    let directory =
        fs::File::open(parent).map_err(|error| AppError::path("打开父目录", parent, error))?;
    directory
        .sync_all()
        .map_err(|error| AppError::path("同步父目录", parent, error))
}

#[cfg(not(unix))]
fn sync_parent(_parent: &Path) -> Result<()> {
    Ok(())
}

#[cfg(windows)]
fn restrict_to_current_user(path: &Path) -> Result<()> {
    let username = std::env::var("USERNAME")
        .map_err(|_| AppError::InvalidState("无法确定当前 Windows 用户".into()))?;
    let identity = match std::env::var("USERDOMAIN") {
        Ok(domain) if !domain.is_empty() => format!("{domain}\\{username}"),
        _ => username,
    };
    let status = std::process::Command::new("icacls.exe")
        .arg(path)
        .args([
            "/inheritance:r",
            "/grant:r",
            "*S-1-5-18:(F)",
            "*S-1-5-32-544:(F)",
        ])
        .arg(format!("{identity}:(F)"))
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map_err(|error| AppError::io(format!("限制文件权限 {}", path.display()), error))?;
    if status.success() {
        Ok(())
    } else {
        Err(AppError::InvalidState(format!(
            "无法将 {} 限制为当前用户访问",
            path.display()
        )))
    }
}

#[cfg(not(windows))]
fn restrict_to_current_user(_path: &Path) -> Result<()> {
    Ok(())
}
