use crate::error::{AppError, Result};
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
        let installation = find_installation().ok_or(AppError::AppNotInstalled)?;
        validate_official(&installation)?;
        terminate_exact(&installation.executable, Duration::from_secs(10))?;
        launch(&installation)
    }
}

struct Installation {
    display_path: PathBuf,
    executable: PathBuf,
    version: Option<String>,
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
fn find_installation() -> Option<Installation> {
    let home = dirs::home_dir()?;
    let candidates = [
        PathBuf::from("/Applications/Codex.app"),
        PathBuf::from("/Applications/ChatGPT.app"),
        home.join("Applications/Codex.app"),
        home.join("Applications/ChatGPT.app"),
    ];
    candidates.into_iter().find_map(|bundle| {
        let plist_path = bundle.join("Contents/Info.plist");
        let value = plist::Value::from_file(&plist_path).ok()?;
        let dictionary = value.as_dictionary()?;
        if dictionary.get("CFBundleIdentifier")?.as_string()? != "com.openai.codex" {
            return None;
        }
        let executable_name = dictionary.get("CFBundleExecutable")?.as_string()?;
        let executable = bundle.join("Contents/MacOS").join(executable_name);
        executable.is_file().then(|| Installation {
            display_path: bundle,
            executable,
            version: dictionary
                .get("CFBundleShortVersionString")
                .and_then(plist::Value::as_string)
                .map(ToString::to_string),
        })
    })
}

#[cfg(target_os = "windows")]
fn find_installation() -> Option<Installation> {
    let mut candidates = Vec::new();
    if let Some(local) = dirs::data_local_dir() {
        candidates.extend([
            local.join("Programs/Codex/Codex.exe"),
            local.join("Programs/OpenAI Codex/Codex.exe"),
            local.join("Programs/ChatGPT/ChatGPT.exe"),
        ]);
    }
    for variable in ["ProgramFiles", "ProgramFiles(x86)"] {
        if let Some(root) = std::env::var_os(variable) {
            let root = PathBuf::from(root);
            candidates.extend([
                root.join("Codex/Codex.exe"),
                root.join("OpenAI/Codex/Codex.exe"),
                root.join("OpenAI/ChatGPT/ChatGPT.exe"),
            ]);
        }
    }
    candidates
        .into_iter()
        .find(|path| path.is_file())
        .map(|executable| Installation {
            display_path: executable.clone(),
            executable,
            version: None,
        })
        .or_else(find_packaged_windows_installation)
}

#[cfg(target_os = "windows")]
fn find_packaged_windows_installation() -> Option<Installation> {
    let script = "$p=Get-AppxPackage | Where-Object { \
        $_.Name -match 'Codex|ChatGPT' -and $_.Publisher -match 'OpenAI' \
        } | Sort-Object Version -Descending | Select-Object -First 1; \
        if($p){Write-Output ($p.InstallLocation + \"`t\" + $p.Version)}";
    let output = Command::new("powershell.exe")
        .args([
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            script,
        ])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8(output.stdout).ok()?;
    let (root, version) = text.trim().split_once('\t')?;
    let root = PathBuf::from(root);
    let executable = find_named_executable(&root, 3)?;
    Some(Installation {
        display_path: root,
        executable,
        version: Some(version.into()),
    })
}

#[cfg(target_os = "windows")]
fn find_named_executable(root: &Path, remaining_depth: u8) -> Option<PathBuf> {
    if remaining_depth == 0 {
        return None;
    }
    let entries = fs::read_dir(root).ok()?;
    for entry in entries.flatten() {
        let file_type = entry.file_type().ok()?;
        if file_type.is_symlink() {
            continue;
        }
        let path = entry.path();
        if file_type.is_file()
            && path
                .file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| {
                    name.eq_ignore_ascii_case("Codex.exe")
                        || name.eq_ignore_ascii_case("ChatGPT.exe")
                })
        {
            return Some(path);
        }
        if file_type.is_dir() {
            if let Some(found) = find_named_executable(&path, remaining_depth - 1) {
                return Some(found);
            }
        }
    }
    None
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
fn find_installation() -> Option<Installation> {
    None
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
