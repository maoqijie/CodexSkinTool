use crate::error::{AppError, Result};
use crate::platform::{Installation, PlatformService};
use crate::process_identity::{self, ProcessIdentity};
use std::collections::HashSet;
use std::net::{Ipv4Addr, SocketAddrV4, TcpListener};
use std::path::Path;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub fn available_port() -> Result<u16> {
    (9341..=9380)
        .find(|port| TcpListener::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, *port)).is_ok())
        .ok_or_else(|| AppError::AppControl("本机 9341-9380 端口均不可用".into()))
}

pub fn wait_for_root(
    installation: &Installation,
    existing: &HashSet<u32>,
    port: u16,
) -> Result<ProcessIdentity> {
    let deadline = Instant::now() + Duration::from_secs(15);
    while Instant::now() < deadline {
        if let Some(root) = find_root(installation, existing, port) {
            return Ok(root);
        }
        thread::sleep(Duration::from_millis(200));
    }
    Err(AppError::AppControl("等待 Codex 图片模式进程超时".into()))
}

pub fn find_root(
    installation: &Installation,
    existing: &HashSet<u32>,
    port: u16,
) -> Option<ProcessIdentity> {
    PlatformService::matching_pids(installation)
        .into_iter()
        .filter(|pid| !existing.contains(pid))
        .filter_map(process_identity::snapshot)
        .find(|identity| {
            PlatformService::process_in_installation(installation, identity.pid)
                && command_has_debug_port(identity, port)
        })
}

pub fn wait_for_listener(
    root: &ProcessIdentity,
    port: u16,
    install_root: &Path,
) -> Result<ProcessIdentity> {
    let roots = HashSet::from([root.pid]);
    let deadline = Instant::now() + Duration::from_secs(15);
    while Instant::now() < deadline {
        for pid in process_identity::listener_pids(port)? {
            if process_identity::ancestor_root(pid, &roots, install_root) == Some(root.pid) {
                return process_identity::snapshot(pid)
                    .ok_or_else(|| AppError::AppControl("无法记录 Codex listener 身份".into()));
            }
        }
        thread::sleep(Duration::from_millis(200));
    }
    Err(AppError::AppControl("等待 Codex 回环调试端口超时".into()))
}

pub fn root_matches(identity: &ProcessIdentity, executable: &Path, port: u16) -> bool {
    process_identity::executable_matches(identity, executable)
        && command_has_debug_port(identity, port)
}

pub fn helper_matches(
    identity: &ProcessIdentity,
    helper_path: &Path,
    port: u16,
    session_id: &str,
) -> bool {
    process_identity::executable_matches(identity, helper_path)
        && process_identity::command_contains(
            identity,
            &[
                "--background-helper".into(),
                "--port".into(),
                port.to_string(),
                "--lease-token".into(),
                session_id.into(),
            ],
        )
}

pub fn stop_managed(
    helper: Option<&ProcessIdentity>,
    helper_path: &Path,
    session_id: &str,
    root: Option<&ProcessIdentity>,
    executable: &Path,
    install_root: &Path,
    port: u16,
) -> Result<()> {
    let mut failure = None;
    if let Some(helper) = helper.filter(|identity| process_identity::matches(identity)) {
        if !helper_matches(helper, helper_path, port, session_id) {
            failure = Some(AppError::AppControl(
                "helper 身份不一致，已拒绝结束未知进程".into(),
            ));
        } else if let Err(error) = terminate_and_wait(helper) {
            failure = Some(error);
        }
    }
    if let Some(root) = root.filter(|identity| process_identity::matches(identity)) {
        if !root_matches(root, executable, port) {
            failure.get_or_insert_with(|| {
                AppError::AppControl("Codex 会话身份不一致，已拒绝结束未知进程".into())
            });
        } else {
            match process_identity::verified_tree(root, install_root) {
                Ok(members) => {
                    for member in members {
                        if process_identity::matches(&member) {
                            if let Err(error) = terminate_and_wait(&member) {
                                failure.get_or_insert(error);
                            }
                        }
                    }
                }
                Err(error) => {
                    failure.get_or_insert(error);
                }
            }
        }
    }
    if !process_identity::listener_pids(port)?.is_empty() {
        return Err(AppError::AppControl(
            "Codex 调试端口仍被占用，已保留会话状态".into(),
        ));
    }
    failure.map_or(Ok(()), Err)
}

fn terminate_and_wait(identity: &ProcessIdentity) -> Result<()> {
    process_identity::terminate_verified(identity)?;
    process_identity::wait_for_exit(identity, Duration::from_secs(5));
    Ok(())
}

fn command_has_debug_port(identity: &ProcessIdentity, port: u16) -> bool {
    process_identity::command_contains(
        identity,
        &[
            "--remote-debugging-address=127.0.0.1".into(),
            format!("--remote-debugging-port={port}"),
        ],
    )
}

pub fn unix_time() -> Result<u64> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_secs())
        .map_err(|_| AppError::InvalidState("系统时间无效".into()))
}
