use crate::error::{AppError, Result};
use crate::paths::AppPaths;
use crate::process_identity;
use serde::Deserialize;
use std::fs::{self, OpenOptions};
use std::path::PathBuf;
use std::thread;
use std::time::{Duration, Instant};
use uuid::Uuid;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyIdentity {
    pid: u32,
    started_at: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacySessionState {
    version: u8,
    port: u16,
    helper_path: PathBuf,
    #[serde(rename = "sessionID")]
    session_id: String,
    helper: Option<LegacyIdentity>,
    codex: Option<LegacyIdentity>,
}

pub fn recover(paths: &AppPaths) -> Result<bool> {
    let state_path = paths.support.join("background-session.json");
    let data = fs::read(&state_path)
        .map_err(|error| AppError::path("读取旧图片会话", &state_path, error))?;
    let legacy = match serde_json::from_slice::<LegacySessionState>(&data) {
        Ok(state) if state.version == 2 && Uuid::parse_str(&state.session_id).is_ok() => state,
        _ => return Ok(false),
    };
    let _ = fs::remove_file(paths.support.join("background-session.lease"));
    if let Some(helper) = legacy.helper.as_ref() {
        stop_helper(&legacy, helper)?;
    }
    if let Some(codex) = legacy.codex.as_ref() {
        stop_codex(&legacy, codex)?;
    }
    clear(paths);
    Ok(true)
}

fn stop_helper(legacy: &LegacySessionState, helper: &LegacyIdentity) -> Result<()> {
    let Some(identity) = process_identity::snapshot(helper.pid) else {
        return Ok(());
    };
    let expected_path = fs::canonicalize(&legacy.helper_path)
        .map_err(|error| AppError::path("解析旧 helper 路径", &legacy.helper_path, error))?;
    let expected_args = [
        "--port".into(),
        legacy.port.to_string(),
        "--lease-token".into(),
        legacy.session_id.clone(),
    ];
    if !process_identity::executable_matches(&identity, &expected_path)
        || !process_identity::command_contains(&identity, &expected_args)
        || !process_identity::legacy_start_matches(&identity, &helper.started_at)
    {
        return Err(AppError::AppControl(
            "旧 helper 身份不一致，已拒绝结束未知进程".into(),
        ));
    }
    wait_for_exit(&identity, Duration::from_secs(5));
    if process_identity::matches(&identity) {
        process_identity::terminate_verified(&identity)?;
        wait_for_exit(&identity, Duration::from_secs(5));
    }
    Ok(())
}

pub fn open_log(paths: &AppPaths) -> Result<fs::File> {
    let path = paths.support.join("background-helper.log");
    crate::atomic::write_private(&path, b"")?;
    let mut options = OpenOptions::new();
    options.create(true).append(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options
        .open(&path)
        .map_err(|error| AppError::path("打开图片 helper 日志", &path, error))
}

fn stop_codex(legacy: &LegacySessionState, codex: &LegacyIdentity) -> Result<()> {
    if !process_identity::listener_pids(legacy.port)?.contains(&codex.pid) {
        return Ok(());
    }
    let installation = crate::platform::PlatformService::verified_installation()?;
    let Some(identity) = process_identity::snapshot(codex.pid) else {
        return Ok(());
    };
    if !process_identity::executable_matches(&identity, &installation.executable)
        || !process_identity::legacy_start_matches(&identity, &codex.started_at)
    {
        return Err(AppError::AppControl(
            "旧 Codex 会话身份不一致，已拒绝结束未知进程".into(),
        ));
    }
    process_identity::terminate_verified(&identity)?;
    process_identity::wait_for_exit(&identity, Duration::from_secs(10));
    Ok(())
}

fn clear(paths: &AppPaths) {
    for name in [
        "background-session.json",
        "background-ready.json",
        "background-session.lease",
    ] {
        let _ = fs::remove_file(paths.support.join(name));
    }
}

fn wait_for_exit(identity: &process_identity::ProcessIdentity, timeout: Duration) {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline && process_identity::matches(identity) {
        thread::sleep(Duration::from_millis(100));
    }
}
