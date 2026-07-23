use crate::error::{AppError, Result};
use serde::{Deserialize, Serialize};
use std::cmp::Reverse;
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
#[cfg(target_os = "macos")]
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};
use sysinfo::{Pid, ProcessesToUpdate, Signal, System};

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProcessIdentity {
    pub pid: u32,
    pub started_at: u64,
}

pub fn snapshot(pid: u32) -> Option<ProcessIdentity> {
    let mut system = System::new();
    system.refresh_processes(ProcessesToUpdate::All, true);
    let process = system.process(Pid::from_u32(pid))?;
    Some(ProcessIdentity {
        pid,
        started_at: identity_start_time(pid, process.start_time())?,
    })
}

pub fn matches(identity: &ProcessIdentity) -> bool {
    snapshot(identity.pid).is_some_and(|actual| actual == *identity)
}

pub fn executable_matches(identity: &ProcessIdentity, executable: &Path) -> bool {
    if !matches(identity) {
        return false;
    }
    process_executable(identity.pid).is_some_and(|path| paths_equal(&path, executable))
}

pub fn command_contains(identity: &ProcessIdentity, values: &[String]) -> bool {
    if !matches(identity) {
        return false;
    }
    let mut system = System::new();
    system.refresh_processes(ProcessesToUpdate::All, true);
    let Some(process) = system.process(Pid::from_u32(identity.pid)) else {
        return false;
    };
    let command: Vec<String> = process
        .cmd()
        .iter()
        .map(|part| part.to_string_lossy().into_owned())
        .collect();
    values.iter().all(|value| command.contains(value))
}

#[cfg(target_os = "macos")]
pub fn legacy_start_matches(identity: &ProcessIdentity, expected: &str) -> bool {
    let output = Command::new("/bin/ps")
        .args(["-p", &identity.pid.to_string(), "-o", "lstart="])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output();
    output.is_ok_and(|output| {
        output.status.success() && String::from_utf8_lossy(&output.stdout).trim() == expected
    })
}

#[cfg(not(target_os = "macos"))]
pub fn legacy_start_matches(_identity: &ProcessIdentity, _expected: &str) -> bool {
    false
}

pub fn listener_pids(port: u16) -> Result<HashSet<u32>> {
    listener_pids_impl(port)
        .ok_or_else(|| AppError::AppControl("无法查询 Codex 调试端口监听进程".into()))
}

#[cfg(target_os = "windows")]
fn listener_pids_impl(port: u16) -> Option<HashSet<u32>> {
    crate::process_identity_windows::listener_pids(port)
}

pub fn listener_belongs_to(
    listener_pid: u32,
    roots: &HashSet<u32>,
    installation_root: &Path,
) -> bool {
    ancestor_root(listener_pid, roots, installation_root).is_some()
}

pub fn ancestor_root(
    listener_pid: u32,
    roots: &HashSet<u32>,
    installation_root: &Path,
) -> Option<u32> {
    let mut system = System::new();
    system.refresh_processes(ProcessesToUpdate::All, true);
    let mut pid = Pid::from_u32(listener_pid);
    let root = fs::canonicalize(installation_root).ok()?;
    for _ in 0..32 {
        let process = system.process(pid)?;
        let executable = process.exe().and_then(|path| fs::canonicalize(path).ok())?;
        if !path_is_within(&executable, &root) {
            return None;
        }
        if roots.contains(&pid.as_u32()) {
            return Some(pid.as_u32());
        }
        pid = process.parent()?;
    }
    None
}

pub fn verified_tree(
    root: &ProcessIdentity,
    installation_root: &Path,
) -> Result<Vec<ProcessIdentity>> {
    if !matches(root) {
        return Ok(Vec::new());
    }
    let mut system = System::new();
    system.refresh_processes(ProcessesToUpdate::All, true);
    let root_path = fs::canonicalize(installation_root)
        .map_err(|error| AppError::path("解析 Codex 安装目录", installation_root, error))?;
    let mut members = Vec::new();
    for (pid, process) in system.processes() {
        let Some(depth) = descendant_depth(*pid, root.pid, &system) else {
            continue;
        };
        let executable = process
            .exe()
            .and_then(|path| fs::canonicalize(path).ok())
            .ok_or_else(|| AppError::AppControl("无法验证 Codex 子进程路径".into()))?;
        if !path_is_within(&executable, &root_path) {
            continue;
        }
        members.push((
            depth,
            ProcessIdentity {
                pid: pid.as_u32(),
                started_at: identity_start_time(pid.as_u32(), process.start_time())
                    .ok_or_else(|| AppError::AppControl("无法记录 Codex 子进程创建时间".into()))?,
            },
        ));
    }
    members.sort_by_key(|member| Reverse(member.0));
    Ok(members.into_iter().map(|(_, identity)| identity).collect())
}

pub fn terminate_verified(identity: &ProcessIdentity) -> Result<()> {
    let mut system = System::new();
    system.refresh_processes(ProcessesToUpdate::All, true);
    let process = system
        .process(Pid::from_u32(identity.pid))
        .filter(|process| {
            identity_start_time(identity.pid, process.start_time()) == Some(identity.started_at)
        })
        .ok_or_else(|| AppError::AppControl("进程身份已变化，拒绝结束未知进程".into()))?;
    if process
        .kill_with(Signal::Term)
        .unwrap_or_else(|| process.kill())
    {
        Ok(())
    } else {
        Err(AppError::AppControl(format!(
            "无法结束已验证进程 {}",
            identity.pid
        )))
    }
}

pub fn wait_for_exit(identity: &ProcessIdentity, timeout: Duration) {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline && matches(identity) {
        thread::sleep(Duration::from_millis(100));
    }
}

fn process_executable(pid: u32) -> Option<PathBuf> {
    let mut system = System::new();
    system.refresh_processes(ProcessesToUpdate::All, true);
    let path = system.process(Pid::from_u32(pid))?.exe()?;
    fs::canonicalize(path).ok()
}

fn descendant_depth(pid: Pid, root: u32, system: &System) -> Option<usize> {
    let mut current = pid;
    for depth in 0..32 {
        if current.as_u32() == root {
            return Some(depth);
        }
        current = system.process(current)?.parent()?;
    }
    None
}

#[cfg(target_os = "macos")]
fn listener_pids_impl(port: u16) -> Option<HashSet<u32>> {
    let output = Command::new("/usr/sbin/lsof")
        .args(["-nP", "-a", &format!("-iTCP:{port}"), "-sTCP:LISTEN", "-Fp"])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !output.status.success() && output.status.code() != Some(1) {
        return None;
    }
    Some(
        String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter_map(|line| line.strip_prefix('p')?.parse().ok())
            .collect(),
    )
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
fn listener_pids_impl(_port: u16) -> Option<HashSet<u32>> {
    None
}

#[cfg(not(windows))]
fn identity_start_time(_pid: u32, fallback: u64) -> Option<u64> {
    Some(fallback)
}

#[cfg(windows)]
fn identity_start_time(pid: u32, _fallback: u64) -> Option<u64> {
    process_start_time(pid)
}

#[cfg(windows)]
fn process_start_time(pid: u32) -> Option<u64> {
    use windows::Win32::Foundation::{CloseHandle, FILETIME};
    use windows::Win32::System::Threading::{
        GetProcessTimes, OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION,
    };
    let handle = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) }.ok()?;
    let mut creation = FILETIME::default();
    let mut exit = FILETIME::default();
    let mut kernel = FILETIME::default();
    let mut user = FILETIME::default();
    let result =
        unsafe { GetProcessTimes(handle, &mut creation, &mut exit, &mut kernel, &mut user) };
    let _ = unsafe { CloseHandle(handle) };
    result.ok()?;
    Some((u64::from(creation.dwHighDateTime) << 32) | u64::from(creation.dwLowDateTime))
}

#[cfg(windows)]
fn paths_equal(left: &Path, right: &Path) -> bool {
    left.to_string_lossy()
        .eq_ignore_ascii_case(&right.to_string_lossy())
}

#[cfg(not(windows))]
fn paths_equal(left: &Path, right: &Path) -> bool {
    left == right
}

#[cfg(windows)]
fn path_is_within(path: &Path, root: &Path) -> bool {
    let path: Vec<String> = path
        .components()
        .map(|part| part.as_os_str().to_string_lossy().to_ascii_lowercase())
        .collect();
    let root: Vec<String> = root
        .components()
        .map(|part| part.as_os_str().to_string_lossy().to_ascii_lowercase())
        .collect();
    path.starts_with(&root)
}

#[cfg(not(windows))]
fn path_is_within(path: &Path, root: &Path) -> bool {
    path.starts_with(root)
}
