use crate::atomic;
use crate::background_runtime as runtime;
use crate::error::{AppError, Result};
use crate::models::{BackgroundSkinStatus, CustomThemeDraft};
use crate::paths::AppPaths;
use crate::platform::{Installation, PlatformService};
use crate::process_identity::{self, ProcessIdentity};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};
use uuid::Uuid;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
enum Phase {
    Starting,
    Active,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct SessionState {
    version: u8,
    phase: Phase,
    port: u16,
    helper_path: PathBuf,
    session_id: String,
    helper: Option<ProcessIdentity>,
    root: Option<ProcessIdentity>,
    listener: Option<ProcessIdentity>,
    install_root: PathBuf,
    executable: PathBuf,
    created_at_unix: u64,
    #[serde(default)]
    draft: Option<CustomThemeDraft>,
}

struct PreparedBackground {
    image: PathBuf,
    installation: Installation,
    helper_path: PathBuf,
    install_root: PathBuf,
    executable: PathBuf,
}

pub struct BackgroundSession {
    paths: AppPaths,
}

impl BackgroundSession {
    pub fn new(paths: AppPaths) -> Self {
        Self { paths }
    }

    pub fn status(&self) -> BackgroundSkinStatus {
        let valid = self
            .read_state()
            .ok()
            .flatten()
            .filter(|state| self.state_is_active(state).unwrap_or(false));
        BackgroundSkinStatus {
            active: valid.is_some(),
            port: valid.map(|state| state.port),
        }
    }

    pub fn start(&self, draft: &CustomThemeDraft) -> Result<()> {
        let prepared = self.prepare(draft)?;
        self.stop()?;
        self.start_prepared(draft, prepared)
    }

    fn prepare(&self, draft: &CustomThemeDraft) -> Result<PreparedBackground> {
        let image_name = draft
            .background_image_name
            .as_deref()
            .ok_or_else(|| AppError::InvalidInput("图片主题缺少背景图片".into()))?;
        let image = crate::images::ImageStore::new(&self.paths.support)
            .resolve(Some(image_name))
            .ok_or_else(|| AppError::InvalidImage("已选择的背景图片不存在".into()))?;
        let installation = PlatformService::verified_installation()?;
        if installation.packaged {
            return Err(AppError::BackgroundUnsupported(
                "Windows Store/MSIX 安装暂不能安全传递 CDP 参数，请安装官方桌面版 Codex".into(),
            ));
        }
        fs::create_dir_all(&self.paths.support)
            .map_err(|error| AppError::path("创建图片会话目录", &self.paths.support, error))?;
        let helper_path = fs::canonicalize(
            std::env::current_exe()
                .map_err(|error| AppError::io("确定 CodexSkinTool 可执行文件", error))?,
        )
        .map_err(|error| AppError::io("解析 helper 可执行文件", error))?;
        let install_root = fs::canonicalize(installation.root())
            .map_err(|error| AppError::path("解析 Codex 安装目录", installation.root(), error))?;
        let executable = fs::canonicalize(&installation.executable).map_err(|error| {
            AppError::path("解析 Codex 可执行文件", &installation.executable, error)
        })?;
        Ok(PreparedBackground {
            image,
            installation,
            helper_path,
            install_root,
            executable,
        })
    }

    fn start_prepared(&self, draft: &CustomThemeDraft, prepared: PreparedBackground) -> Result<()> {
        self.clear_files();
        let port = runtime::available_port()?;
        let session_id = Uuid::new_v4().to_string();
        let mut state = SessionState {
            version: 1,
            phase: Phase::Starting,
            port,
            helper_path: prepared.helper_path,
            session_id,
            helper: None,
            root: None,
            listener: None,
            install_root: prepared.install_root,
            executable: prepared.executable,
            created_at_unix: runtime::unix_time()?,
            draft: Some(draft.normalized()),
        };
        self.write_state(&state)?;
        let existing: HashSet<u32> = PlatformService::matching_pids(&prepared.installation)
            .into_iter()
            .collect();
        let result = (|| {
            PlatformService::terminate(&prepared.installation)?;
            PlatformService::launch_debug(&prepared.installation, port)?;
            let root = runtime::wait_for_root(&prepared.installation, &existing, port)?;
            state.root = Some(root);
            self.write_state(&state)?;
            let listener = runtime::wait_for_listener(
                state.root.as_ref().expect("root recorded"),
                state.port,
                &state.install_root,
            )?;
            state.listener = Some(listener);
            self.write_state(&state)?;
            atomic::write_private(&self.lease_path(), state.session_id.as_bytes())?;
            let helper = self.launch_helper(&state, draft, prepared.image)?;
            state.helper = Some(helper);
            self.write_state(&state)?;
            self.wait_for_ready(&state)?;
            state.phase = Phase::Active;
            self.write_state(&state)
        })();
        if let Err(error) = result {
            if state.root.is_none() {
                state.root = runtime::find_root(&prepared.installation, &existing, port);
            }
            if let Err(cleanup) = runtime::stop_managed(
                state.helper.as_ref(),
                &state.helper_path,
                &state.session_id,
                state.root.as_ref(),
                &state.executable,
                &state.install_root,
                state.port,
            ) {
                let _ = self.write_state(&state);
                return Err(AppError::AppControl(format!(
                    "{error}；且图片会话清理失败（{cleanup}）"
                )));
            }
            self.clear_files();
            return Err(error);
        }
        Ok(())
    }

    pub fn transaction_draft(&self) -> Result<Option<CustomThemeDraft>> {
        let Some(state) = self.read_state()? else {
            return Ok(None);
        };
        Ok((state.phase == Phase::Active)
            .then_some(state)
            .and_then(|state| state.draft))
    }

    fn state_is_active(&self, state: &SessionState) -> Result<bool> {
        let session_matches = state.version == 1
            && state.phase == Phase::Active
            && state.draft.is_some()
            && state.root.as_ref().is_some_and(process_identity::matches)
            && state
                .helper
                .as_ref()
                .is_some_and(|helper| self.helper_matches(helper, state));
        if !session_matches {
            return Ok(false);
        }
        match state.listener.as_ref() {
            Some(listener) => self.listener_matches(listener, state),
            None => Ok(false),
        }
    }

    pub fn stop(&self) -> Result<bool> {
        let state = match self.read_state() {
            Ok(Some(state)) => state,
            Ok(None) => {
                self.clear_files();
                return Ok(false);
            }
            Err(_error) if crate::background_legacy::recover(&self.paths)? => return Ok(true),
            Err(error) => return Err(error),
        };
        let _ = fs::remove_file(self.lease_path());
        runtime::stop_managed(
            state.helper.as_ref(),
            &state.helper_path,
            &state.session_id,
            state.root.as_ref(),
            &state.executable,
            &state.install_root,
            state.port,
        )?;
        self.clear_files();
        Ok(true)
    }

    fn launch_helper(
        &self,
        state: &SessionState,
        draft: &CustomThemeDraft,
        image: PathBuf,
    ) -> Result<ProcessIdentity> {
        let ready = self.ready_path();
        let lease = self.lease_path();
        let fit = match draft.background_fit {
            crate::models::BackgroundFit::Cover => "cover",
            crate::models::BackgroundFit::Contain => "contain",
        };
        let log = crate::background_legacy::open_log(&self.paths)?;
        let error_log = log
            .try_clone()
            .map_err(|error| AppError::io("复制图片 helper 日志句柄", error))?;
        let child = Command::new(&state.helper_path)
            .args([
                "--background-helper",
                "--port",
                &state.port.to_string(),
                "--image",
            ])
            .arg(image)
            .args(["--opacity", &draft.background_opacity.to_string()])
            .args(["--blur", &draft.background_blur.to_string()])
            .args(["--fit", fit])
            .args(["--brightness", &draft.background_brightness.to_string()])
            .args(["--focus-x", &draft.background_focus_x.to_string()])
            .args(["--focus-y", &draft.background_focus_y.to_string()])
            .args(["--surface", &draft.surface, "--ink", &draft.ink])
            .arg("--ready-file")
            .arg(ready)
            .arg("--lease-file")
            .arg(lease)
            .args(["--lease-token", &state.session_id])
            .stdin(Stdio::null())
            .stdout(Stdio::from(log))
            .stderr(Stdio::from(error_log))
            .spawn()
            .map_err(|error| AppError::io("启动图片 helper", error))?;
        process_identity::snapshot(child.id())
            .ok_or_else(|| AppError::AppControl("无法记录图片 helper 身份".into()))
    }

    fn wait_for_ready(&self, state: &SessionState) -> Result<()> {
        let deadline = Instant::now() + Duration::from_secs(45);
        while Instant::now() < deadline {
            if state
                .helper
                .as_ref()
                .is_some_and(|helper| !process_identity::matches(helper))
            {
                return Err(AppError::AppControl(
                    "图片 helper 提前退出，请查看 background-helper.log".into(),
                ));
            }
            let listener_ready = match state.listener.as_ref() {
                Some(listener) => self.listener_matches(listener, state)?,
                None => false,
            };
            if self.ready_path().is_file()
                && state
                    .helper
                    .as_ref()
                    .is_some_and(|helper| self.helper_matches(helper, state))
                && listener_ready
            {
                return Ok(());
            }
            thread::sleep(Duration::from_millis(200));
        }
        Err(AppError::AppControl("等待 Codex 图片层验证超时".into()))
    }

    fn helper_matches(&self, identity: &ProcessIdentity, state: &SessionState) -> bool {
        runtime::helper_matches(identity, &state.helper_path, state.port, &state.session_id)
    }

    fn listener_matches(&self, identity: &ProcessIdentity, state: &SessionState) -> Result<bool> {
        if !state
            .root
            .as_ref()
            .is_some_and(|root| runtime::root_matches(root, &state.executable, state.port))
        {
            return Ok(false);
        }
        let roots = state.root.iter().map(|root| root.pid).collect();
        Ok(process_identity::matches(identity)
            && process_identity::listener_pids(state.port)?.contains(&identity.pid)
            && process_identity::listener_belongs_to(identity.pid, &roots, &state.install_root))
    }

    fn state_path(&self) -> PathBuf {
        self.paths.support.join("background-session.json")
    }
    fn ready_path(&self) -> PathBuf {
        self.paths.support.join("background-ready.json")
    }
    fn lease_path(&self) -> PathBuf {
        self.paths.support.join("background-session.lease")
    }
    fn read_state(&self) -> Result<Option<SessionState>> {
        let path = self.state_path();
        if !path.exists() {
            return Ok(None);
        }
        let state: SessionState = serde_json::from_slice(
            &fs::read(&path).map_err(|error| AppError::path("读取图片会话", &path, error))?,
        )?;
        if state.version != 1 || Uuid::parse_str(&state.session_id).is_err() {
            return Err(AppError::InvalidState("图片会话状态无效".into()));
        }
        Ok(Some(state))
    }
    fn write_state(&self, state: &SessionState) -> Result<()> {
        atomic::write_private(&self.state_path(), &serde_json::to_vec_pretty(state)?)
    }
    fn clear_files(&self) {
        let _ = fs::remove_file(self.state_path());
        let _ = fs::remove_file(self.ready_path());
        let _ = fs::remove_file(self.lease_path());
    }
}
