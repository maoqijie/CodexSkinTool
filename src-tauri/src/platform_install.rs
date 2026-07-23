use crate::platform::Installation;
use std::path::PathBuf;

#[cfg(target_os = "macos")]
pub fn find_installation() -> Option<Installation> {
    let home = dirs::home_dir()?;
    [
        PathBuf::from("/Applications/Codex.app"),
        PathBuf::from("/Applications/ChatGPT.app"),
        home.join("Applications/Codex.app"),
        home.join("Applications/ChatGPT.app"),
    ]
    .into_iter()
    .find_map(|bundle| {
        let value = plist::Value::from_file(bundle.join("Contents/Info.plist")).ok()?;
        let dictionary = value.as_dictionary()?;
        if dictionary.get("CFBundleIdentifier")?.as_string()? != "com.openai.codex" {
            return None;
        }
        let executable = bundle
            .join("Contents/MacOS")
            .join(dictionary.get("CFBundleExecutable")?.as_string()?);
        executable.is_file().then(|| Installation {
            display_path: bundle,
            executable,
            version: dictionary
                .get("CFBundleShortVersionString")
                .and_then(plist::Value::as_string)
                .map(ToString::to_string),
            packaged: false,
        })
    })
}

#[cfg(target_os = "windows")]
pub fn find_installation() -> Option<Installation> {
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
            packaged: false,
        })
        .or_else(find_packaged_windows_installation)
}

#[cfg(target_os = "windows")]
fn find_packaged_windows_installation() -> Option<Installation> {
    use std::process::{Command, Stdio};
    let script = "$p=Get-AppxPackage | Where-Object { $_.Name -match 'Codex|ChatGPT' -and $_.Publisher -match 'OpenAI' } | Sort-Object Version -Descending | Select-Object -First 1; if($p){Write-Output ($p.InstallLocation + \"`t\" + $p.Version)}";
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
    let text = output
        .status
        .success()
        .then(|| String::from_utf8(output.stdout).ok())??;
    let (root, version) = text.trim().split_once('\t')?;
    let root = PathBuf::from(root);
    Some(Installation {
        executable: find_named_executable(&root, 3)?,
        display_path: root,
        version: Some(version.into()),
        packaged: true,
    })
}

#[cfg(target_os = "windows")]
fn find_named_executable(root: &std::path::Path, depth: u8) -> Option<PathBuf> {
    if depth == 0 {
        return None;
    }
    for entry in std::fs::read_dir(root).ok()?.flatten() {
        let file_type = entry.file_type().ok()?;
        if file_type.is_symlink() {
            continue;
        }
        let path = entry.path();
        let named = path
            .file_name()
            .and_then(|name| name.to_str())
            .is_some_and(|name| {
                name.eq_ignore_ascii_case("Codex.exe") || name.eq_ignore_ascii_case("ChatGPT.exe")
            });
        if file_type.is_file() && named {
            return Some(path);
        }
        if file_type.is_dir() {
            if let Some(found) = find_named_executable(&path, depth - 1) {
                return Some(found);
            }
        }
    }
    None
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn find_installation() -> Option<Installation> {
    None
}
