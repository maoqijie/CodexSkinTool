use crate::atomic;
use crate::cdp;
use crate::error::{AppError, Result};
use crate::models::BackgroundFit;
use base64::Engine;
use serde::Serialize;
use serde_json::{json, Value};
use std::fs;
use std::path::PathBuf;
use std::thread;
use std::time::{Duration, Instant};
use uuid::Uuid;

const ERROR_REPEAT_INTERVAL: Duration = Duration::from_secs(30);

#[derive(Clone, Debug)]
struct Options {
    port: u16,
    image: PathBuf,
    opacity: f64,
    blur: f64,
    fit: BackgroundFit,
    brightness: f64,
    focus_x: f64,
    focus_y: f64,
    surface: String,
    ink: String,
    ready_file: PathBuf,
    lease_file: PathBuf,
    lease_token: String,
}

pub fn run_if_requested() -> bool {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    if !arguments.iter().any(|value| value == "--background-helper") {
        return false;
    }
    if let Err(error) = Options::parse(&arguments).and_then(run) {
        eprintln!("CodexSkinTool helper: {error}");
        std::process::exit(1);
    }
    true
}

fn run(options: Options) -> Result<()> {
    wait_for_lease(&options)?;
    let data = fs::read(&options.image)
        .map_err(|error| AppError::path("读取背景图片", &options.image, error))?;
    if data.len() > 16 * 1_024 * 1_024 {
        return Err(AppError::InvalidImage("背景 PNG 超过 16 MB".into()));
    }
    let image = image::load_from_memory_with_format(&data, image::ImageFormat::Png)
        .map_err(|error| AppError::InvalidImage(format!("背景 PNG 解码失败：{error}")))?;
    if image.width() < 320
        || image.height() < 240
        || u64::from(image.width()) * u64::from(image.height()) > 40_000_000
    {
        return Err(AppError::InvalidImage("背景 PNG 未通过尺寸限制".into()));
    }
    let data_url = format!(
        "data:image/png;base64,{}",
        base64::engine::general_purpose::STANDARD.encode(data)
    );
    let inject = injection_expression(&options, &data_url)?;
    let verify = verification_expression(&options)?;
    let probe = probe_expression();
    let mut ready = false;
    let mut retry_log = RetryLog::default();
    while lease_is_valid(&options) {
        match apply_to_targets(&options, probe, &inject, &verify) {
            Ok(()) => {
                retry_log.recovered();
                if !ready {
                    atomic::write_private(&options.ready_file, b"{\"status\":\"ready\"}\n")?;
                    ready = true;
                }
            }
            Err(error) => retry_log.failure(&error),
        }
        thread::sleep(if ready {
            Duration::from_secs(2)
        } else {
            Duration::from_millis(350)
        });
    }
    Ok(())
}

fn apply_to_targets(options: &Options, probe: &str, inject: &str, verify: &str) -> Result<()> {
    let targets = cdp::list_targets(options.port)?;
    if targets.is_empty() {
        return Err(AppError::AppControl(
            "未找到可信的 Codex app:// 页面".into(),
        ));
    }
    let mut applied = false;
    let mut last_error = None;
    for target in targets {
        match apply_to_target(options, &target, probe, inject, verify) {
            Ok(()) => applied = true,
            Err(error) => last_error = Some(error),
        }
    }
    if applied {
        Ok(())
    } else {
        Err(last_error.unwrap_or_else(|| AppError::AppControl("Codex 图片注入失败".into())))
    }
}

fn apply_to_target(
    options: &Options,
    target: &cdp::Target,
    probe: &str,
    inject: &str,
    verify: &str,
) -> Result<()> {
    let socket = cdp::validated_socket_url(target, options.port)?;
    let identified = cdp::evaluate(socket.clone(), probe)?;
    if identified.pointer("/codex") != Some(&Value::Bool(true)) {
        return Err(AppError::AppControl("Codex DOM 身份探针未通过".into()));
    }
    if cdp::evaluate(socket.clone(), inject)? != Value::Bool(true) {
        return Err(AppError::AppControl("Codex 图片层注入未成功".into()));
    }
    if cdp::evaluate(socket, verify)? != Value::Bool(true) {
        return Err(AppError::AppControl(
            "Codex 图片层 computed style 验证未通过".into(),
        ));
    }
    Ok(())
}

#[derive(Default)]
struct RetryLog {
    last_error: Option<String>,
    last_emitted: Option<Instant>,
}

impl RetryLog {
    fn failure(&mut self, error: &AppError) {
        let message = error.to_string();
        if self.should_emit(&message, Instant::now()) {
            eprintln!("CodexSkinTool helper retry: {message}");
        }
    }

    fn should_emit(&mut self, message: &str, now: Instant) -> bool {
        let changed = self.last_error.as_deref() != Some(message);
        let interval_elapsed = self.last_emitted.map_or(true, |last| {
            now.duration_since(last) >= ERROR_REPEAT_INTERVAL
        });
        self.last_error = Some(message.into());
        if changed || interval_elapsed {
            self.last_emitted = Some(now);
            true
        } else {
            false
        }
    }

    fn recovered(&mut self) {
        if self.last_error.take().is_some() {
            eprintln!("CodexSkinTool helper: CDP 图片注入已恢复");
        }
        self.last_emitted = None;
    }
}

impl Options {
    fn parse(arguments: &[String]) -> Result<Self> {
        fn value(arguments: &[String], flag: &str) -> Result<String> {
            let index = arguments
                .iter()
                .position(|value| value == flag)
                .ok_or_else(|| AppError::InvalidInput(format!("缺少参数 {flag}")))?;
            arguments
                .get(index + 1)
                .cloned()
                .ok_or_else(|| AppError::InvalidInput(format!("缺少参数 {flag}")))
        }
        let number = |flag: &str| -> Result<f64> {
            value(arguments, flag)?
                .parse()
                .map_err(|_| AppError::InvalidInput(format!("参数 {flag} 无效")))
        };
        let port = value(arguments, "--port")?
            .parse()
            .map_err(|_| AppError::InvalidInput("调试端口无效".into()))?;
        let fit = serde_json::from_value(Value::String(value(arguments, "--fit")?))?;
        let lease_token = value(arguments, "--lease-token")?;
        let opacity = number("--opacity")?;
        let blur = number("--blur")?;
        let brightness = number("--brightness")?;
        let focus_x = number("--focus-x")?;
        let focus_y = number("--focus-y")?;
        let surface = value(arguments, "--surface")?;
        let ink = value(arguments, "--ink")?;
        if !(1024..=65535).contains(&port)
            || !(0.08..=0.85).contains(&opacity)
            || !(0.0..=24.0).contains(&blur)
            || !(0.45..=1.25).contains(&brightness)
            || !(0.0..=1.0).contains(&focus_x)
            || !(0.0..=1.0).contains(&focus_y)
            || !valid_color(&surface)
            || !valid_color(&ink)
            || Uuid::parse_str(&lease_token).is_err()
        {
            return Err(AppError::InvalidInput("helper 参数值无效".into()));
        }
        Ok(Self {
            port,
            image: value(arguments, "--image")?.into(),
            opacity,
            blur,
            fit,
            brightness,
            focus_x,
            focus_y,
            surface,
            ink,
            ready_file: value(arguments, "--ready-file")?.into(),
            lease_file: value(arguments, "--lease-file")?.into(),
            lease_token,
        })
    }
}

fn wait_for_lease(options: &Options) -> Result<()> {
    let deadline = Instant::now() + Duration::from_secs(5);
    while Instant::now() < deadline {
        if lease_is_valid(options) {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(50));
    }
    Err(AppError::AppControl("父进程未建立有效图片租约".into()))
}

fn lease_is_valid(options: &Options) -> bool {
    fs::read(&options.lease_file)
        .is_ok_and(|data| data.len() <= 64 && data.as_slice() == options.lease_token.as_bytes())
}

fn valid_color(value: &str) -> bool {
    value.len() == 7
        && value.starts_with('#')
        && value.as_bytes()[1..].iter().all(u8::is_ascii_hexdigit)
}

fn probe_expression() -> &'static str {
    "(() => ({ codex: Boolean(document.querySelector('main.main-surface, main.browser-main-surface') && document.querySelector('.app-shell-left-panel, aside') && document.querySelector('[role=\"main\"]')) }))()"
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ScriptConfig<'a> {
    image: &'a str,
    opacity: f64,
    blur: f64,
    fit: &'a str,
    brightness: f64,
    focus_x: f64,
    focus_y: f64,
    surface: &'a str,
    ink: &'a str,
    session: &'a str,
}

fn script_config<'a>(options: &'a Options, image: &'a str) -> ScriptConfig<'a> {
    ScriptConfig {
        image,
        opacity: options.opacity,
        blur: options.blur,
        fit: match options.fit {
            BackgroundFit::Cover => "cover",
            BackgroundFit::Contain => "contain",
        },
        brightness: options.brightness,
        focus_x: options.focus_x,
        focus_y: options.focus_y,
        surface: &options.surface,
        ink: &options.ink,
        session: &options.lease_token,
    }
}

fn injection_expression(options: &Options, data_url: &str) -> Result<String> {
    let cfg = serde_json::to_string(&script_config(options, data_url))?;
    Ok(format!(
        r#"(() => {{
          const cfg = {cfg};
          const current = document.getElementById('codex-skin-tool-style');
          if (current?.dataset.session === cfg.session && document.getElementById('codex-skin-tool-background') && document.documentElement.dataset.codexSkinTool === 'background-v2') return true;
          current?.remove(); document.getElementById('codex-skin-tool-background')?.remove();
          const style = document.createElement('style'); style.id = 'codex-skin-tool-style'; style.dataset.session = cfg.session;
          style.textContent = `#codex-skin-tool-background {{ position: fixed; inset: 0; z-index: 0; pointer-events: none; background: ${{cfg.focusX * 100}}% ${{cfg.focusY * 100}}% / ${{cfg.fit}} no-repeat url("${{cfg.image}}"); opacity: ${{cfg.opacity}}; filter: brightness(${{cfg.brightness}}) blur(${{cfg.blur}}px); transform: scale(${{cfg.blur > 0 ? 1.04 : 1}}); }} #root, body > [data-radix-portal] {{ position: relative; z-index: 1; }} body, .main-surface, .browser-main-surface {{ background-color: transparent !important; }} .app-shell-left-panel {{ background-color: color-mix(in srgb, ${{cfg.surface}} 86%, transparent) !important; }} main.main-surface, main.browser-main-surface {{ color: ${{cfg.ink}}; }}`;
          const layer = document.createElement('div'); layer.id = 'codex-skin-tool-background'; layer.setAttribute('aria-hidden', 'true');
          document.head.append(style); document.body.prepend(layer); document.documentElement.dataset.codexSkinTool = 'background-v2'; return true;
        }})()"#
    ))
}

fn verification_expression(options: &Options) -> Result<String> {
    let cfg = json!({
        "opacity": options.opacity, "brightness": options.brightness,
        "focusX": options.focus_x, "focusY": options.focus_y,
        "session": options.lease_token,
    });
    Ok(format!(
        r#"(() => {{ const cfg = {cfg}; const layer = document.getElementById('codex-skin-tool-background'); const style = document.getElementById('codex-skin-tool-style'); if (!layer || !style || style.dataset.session !== cfg.session || document.documentElement.dataset.codexSkinTool !== 'background-v2') return false; const computed = getComputedStyle(layer); return computed.backgroundImage !== 'none' && computed.pointerEvents === 'none' && Math.abs(Number(computed.opacity) - cfg.opacity) < 0.001 && computed.filter.includes(`brightness(${{cfg.brightness}})`) && computed.backgroundPosition === `${{cfg.focusX * 100}}% ${{cfg.focusY * 100}}%`; }})()"#
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_arguments_and_generates_guarded_scripts() {
        let token = Uuid::new_v4().to_string();
        let values = [
            "--background-helper",
            "--port",
            "9341",
            "--image",
            "/tmp/a.png",
            "--opacity",
            "0.28",
            "--blur",
            "2",
            "--fit",
            "cover",
            "--brightness",
            "0.9",
            "--focus-x",
            "0.4",
            "--focus-y",
            "0.6",
            "--surface",
            "#171717",
            "--ink",
            "#F4F4F4",
            "--ready-file",
            "/tmp/ready",
            "--lease-file",
            "/tmp/lease",
            "--lease-token",
            &token,
        ];
        let arguments = values.iter().map(ToString::to_string).collect::<Vec<_>>();
        let options = Options::parse(&arguments).unwrap();
        let inject = injection_expression(&options, "data:image/png;base64,AA==").unwrap();
        assert!(inject.contains("pointer-events: none"));
        assert!(inject.contains("background-v2"));
        assert!(verification_expression(&options)
            .unwrap()
            .contains("getComputedStyle"));
        let mut invalid = arguments;
        let index = invalid
            .iter()
            .position(|value| value == "--focus-x")
            .unwrap();
        invalid[index + 1] = "2".into();
        assert!(Options::parse(&invalid).is_err());
    }

    #[test]
    fn retry_log_deduplicates_and_throttles_repeated_failures() {
        let start = Instant::now();
        let mut log = RetryLog::default();
        assert!(log.should_emit("connection refused", start));
        assert!(!log.should_emit("connection refused", start + Duration::from_secs(1)));
        assert!(log.should_emit("probe failed", start + Duration::from_secs(2)));
        assert!(!log.should_emit("probe failed", start + Duration::from_secs(29)));
        assert!(log.should_emit(
            "probe failed",
            start + ERROR_REPEAT_INTERVAL + Duration::from_secs(2)
        ));
        log.recovered();
        assert!(log.should_emit("probe failed", start + Duration::from_secs(40)));
    }
}
