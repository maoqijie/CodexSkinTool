use crate::error::{AppError, Result};
use crate::platform_install::find_installation;
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};
use sysinfo::{Pid, ProcessesToUpdate, Signal, System};

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppStatus {
    pub platform: &'static str,
    pub platform_label: &'static str,
    pub is_installed: bool,
    pub app_path: Option<String>,
    pub version: Option<String>,
    pub is_running: bool,
}

pub struct PlatformService;

impl PlatformService {
    pub fn status() -> AppStatus {
        let installation = find_installation();
        let running = installation
            .as_ref()
            .is_some_and(|item| !matching_processes(&item.executable).is_empty());
        AppStatus {
            platform: platform_name(),
            platform_label: platform_label(),
            is_installed: installation.is_some(),
            app_path: installation
                .as_ref()
                .map(|item| item.display_path.to_string_lossy().into_owned()),
            version: installation.as_ref().and_then(|item| item.version.clone()),
            is_running: running,
        }
    }

    pub fn restart() -> Result<()> {
        let installation = Self::verified_installation()?;
        terminate_exact(&installation.executable, Duration::from_secs(10))?;
        launch(&installation)
    }

    pub(crate) fn verified_installation() -> Result<Installation> {
        let installation = find_installation().ok_or(AppError::AppNotInstalled)?;
        validate_official(&installation)?;
        Ok(installation)
    }

    pub(crate) fn terminate(installation: &Installation) -> Result<()> {
        terminate_exact(&installation.executable, Duration::from_secs(10))
    }

    pub(crate) fn launch_debug(installation: &Installation, port: u16) -> Result<()> {
        launch_with_debugging(installation, port)
    }

    pub(crate) fn matching_pids(installation: &Installation) -> Vec<u32> {
        matching_processes(&installation.executable)
            .into_iter()
            .map(Pid::as_u32)
            .collect()
    }

    pub(crate) fn process_in_installation(installation: &Installation, pid: u32) -> bool {
        let mut system = System::new();
        system.refresh_processes(ProcessesToUpdate::All, true);
        system
            .process(Pid::from_u32(pid))
            .and_then(sysinfo::Process::exe)
            .is_some_and(|path| installation.contains(path))
    }
}

pub(crate) struct Installation {
    pub(crate) display_path: PathBuf,
    pub(crate) executable: PathBuf,
    pub(crate) version: Option<String>,
    pub(crate) packaged: bool,
}

impl Installation {
    pub(crate) fn root(&self) -> &Path {
        #[cfg(target_os = "macos")]
        {
            &self.display_path
        }
        #[cfg(not(target_os = "macos"))]
        {
            self.executable.parent().unwrap_or(&self.display_path)
        }
    }

    pub(crate) fn contains(&self, path: &Path) -> bool {
        let Some(path) = canonical(path) else {
            return false;
        };
        let Some(root) = canonical(self.root()) else {
            return false;
        };
        #[cfg(windows)]
        {
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
        {
            path.starts_with(root)
        }
    }
}

fn matching_processes(executable: &Path) -> Vec<Pid> {
    let Some(expected) = canonical(executable) else {
        return Vec::new();
    };
    let mut system = System::new();
    system.refresh_processes(ProcessesToUpdate::All, true);
    system
        .processes()
        .iter()
        .filter_map(|(pid, process)| {
            let actual = process.exe().and_then(canonical)?;
            paths_equal(&actual, &expected).then_some(*pid)
        })
        .collect()
}

fn terminate_exact(executable: &Path, timeout: Duration) -> Result<()> {
    let mut system = System::new();
    system.refresh_processes(ProcessesToUpdate::All, true);
    let pids = matching_processes(executable);
    for pid in &pids {
        let process = system
            .process(*pid)
            .ok_or_else(|| AppError::AppControl(format!("进程 {pid} 在身份验证后消失")))?;
        let signalled = process
            .kill_with(Signal::Term)
            .unwrap_or_else(|| process.kill());
        if !signalled {
            return Err(AppError::AppControl(format!(
                "无法结束已验证的 Codex 进程 {pid}"
            )));
        }
    }
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if matching_processes(executable).is_empty() {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(150));
    }
    Err(AppError::AppControl(
        "等待 Codex 退出超时，未终止其他进程".into(),
    ))
}

#[cfg(target_os = "macos")]
fn launch(installation: &Installation) -> Result<()> {
    let status = Command::new("/usr/bin/open")
        .args(["-a"])
        .arg(&installation.display_path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|error| AppError::io("启动 Codex", error))?;
    if status.success() {
        Ok(())
    } else {
        Err(AppError::AppControl("系统未能启动 Codex".into()))
    }
}

#[cfg(target_os = "macos")]
fn launch_with_debugging(installation: &Installation, port: u16) -> Result<()> {
    let status = Command::new("/usr/bin/open")
        .arg("-na")
        .arg(&installation.display_path)
        .args([
            "--args",
            "--remote-debugging-address=127.0.0.1",
            &format!("--remote-debugging-port={port}"),
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|error| AppError::io("以图片模式启动 Codex", error))?;
    if status.success() {
        Ok(())
    } else {
        Err(AppError::AppControl("系统未能以图片模式启动 Codex".into()))
    }
}

#[cfg(target_os = "macos")]
fn validate_official(installation: &Installation) -> Result<()> {
    let requirement = "anchor apple generic and identifier \"com.openai.codex\" and certificate leaf[subject.OU] = \"2DC432GLL2\"";
    let status = Command::new("/usr/bin/codesign")
        .args([
            "--verify",
            "--deep",
            "--strict",
            &format!("-R={requirement}"),
        ])
        .arg(&installation.display_path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|error| AppError::io("验证 Codex 签名", error))?;
    if status.success() {
        Ok(())
    } else {
        Err(AppError::AppControl(
            "Codex 签名或发行者不是预期的 OpenAI 官方应用".into(),
        ))
    }
}

#[cfg(target_os = "windows")]
fn launch(installation: &Installation) -> Result<()> {
    Command::new(&installation.executable)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map(|_| ())
        .map_err(|error| AppError::io("启动 Codex", error))
}

#[cfg(target_os = "windows")]
fn launch_with_debugging(installation: &Installation, port: u16) -> Result<()> {
    Command::new(&installation.executable)
        .args([
            "--remote-debugging-address=127.0.0.1",
            &format!("--remote-debugging-port={port}"),
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map(|_| ())
        .map_err(|error| AppError::io("以图片模式启动 Codex", error))
}

#[cfg(target_os = "windows")]
fn validate_official(installation: &Installation) -> Result<()> {
    let script = "$s=Get-AuthenticodeSignature -LiteralPath $env:CODEX_SKIN_VERIFY_PATH; \
        if($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notmatch '(^|, )O=OpenAI(,|$)'){exit 1}";
    let status = Command::new("powershell.exe")
        .args([
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            script,
        ])
        .env("CODEX_SKIN_VERIFY_PATH", &installation.executable)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|error| AppError::io("验证 Codex Authenticode 签名", error))?;
    if status.success() {
        Ok(())
    } else {
        Err(AppError::AppControl(
            "Codex Authenticode 签名或发行者不是预期的 OpenAI 官方应用".into(),
        ))
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
fn launch(_installation: &Installation) -> Result<()> {
    Err(AppError::AppControl("当前平台不受支持".into()))
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
fn launch_with_debugging(_installation: &Installation, _port: u16) -> Result<()> {
    Err(AppError::AppControl("当前平台不受支持".into()))
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
fn validate_official(_installation: &Installation) -> Result<()> {
    Err(AppError::AppControl("当前平台不受支持".into()))
}

fn canonical(path: impl AsRef<Path>) -> Option<PathBuf> {
    fs::canonicalize(path).ok()
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

#[cfg(target_os = "macos")]
const fn platform_name() -> &'static str {
    "macos"
}
#[cfg(target_os = "windows")]
const fn platform_name() -> &'static str {
    "windows"
}
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
const fn platform_name() -> &'static str {
    "other"
}

#[cfg(target_os = "macos")]
const fn platform_label() -> &'static str {
    "macOS"
}
#[cfg(target_os = "windows")]
const fn platform_label() -> &'static str {
    "Windows"
}
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
const fn platform_label() -> &'static str {
    "其他"
}
