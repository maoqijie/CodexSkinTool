use crate::catalog;
use crate::config::ConfigStore;
use crate::error::AppError;
use crate::images::ImageStore;
use crate::library::{ThemeKind, ThemeLibrary};
use crate::models::CustomThemeDraft;
use crate::paths::AppPaths;
use crate::service::{AppService, ApplyRequest};
use image::{ImageBuffer, Rgba};
use std::fs;
use tempfile::TempDir;

#[test]
fn config_apply_preserves_unknown_data_and_restores_only_managed_keys() {
    let root = TempDir::new().unwrap();
    let paths = crate::paths::AppPaths::isolated(root.path());
    fs::create_dir_all(paths.config.parent().unwrap()).unwrap();
    let original = r#"# keep this comment
model = "gpt-5"

[desktop]
appearanceTheme = "light" # original mode
appearanceLightCodeThemeId = "codex"
localeOverride = "zh-CN"

[features]
memories = true
"#;
    fs::write(&paths.config, original).unwrap();
    let store = ConfigStore::new(paths.clone());
    let theme = catalog::theme_by_id("tokyo-night").unwrap();
    store.apply(&theme, &theme.id, true).unwrap();
    let applied = fs::read_to_string(&paths.config).unwrap();
    assert!(applied.contains("model = \"gpt-5\""));
    assert!(applied.contains("localeOverride = \"zh-CN\""));
    assert!(applied.contains("[features]"));
    assert!(applied.contains("appearanceTheme = \"dark\""));
    assert!(applied.contains("appearanceDarkChromeTheme"));
    assert_eq!(
        store
            .read_state()
            .unwrap()
            .unwrap()
            .selected_theme_id
            .as_deref(),
        Some("tokyo-night")
    );

    store.restore(false).unwrap();
    let restored = fs::read_to_string(&paths.config).unwrap();
    assert!(restored.contains("appearanceTheme = \"light\" # original mode"));
    assert!(restored.contains("appearanceLightCodeThemeId = \"codex\""));
    assert!(!restored.contains("appearanceDarkChromeTheme"));
    assert!(restored.contains("memories = true"));
}

#[test]
fn new_config_is_removed_after_restore() {
    let root = TempDir::new().unwrap();
    let paths = crate::paths::AppPaths::isolated(root.path());
    let store = ConfigStore::new(paths.clone());
    let theme = catalog::theme_by_id("codex-dark").unwrap();
    store.apply(&theme, &theme.id, false).unwrap();
    assert!(paths.config.exists());
    assert!(store.restore(false).unwrap());
    assert!(!paths.config.exists());
}

#[test]
fn restore_does_not_leave_a_new_desktop_table() {
    let root = TempDir::new().unwrap();
    let paths = crate::paths::AppPaths::isolated(root.path());
    fs::create_dir_all(paths.config.parent().unwrap()).unwrap();
    fs::write(&paths.config, "model = \"gpt-5\"\n").unwrap();
    let store = ConfigStore::new(paths.clone());
    let theme = catalog::theme_by_id("github-light").unwrap();
    store.apply(&theme, &theme.id, false).unwrap();
    store.restore(false).unwrap();
    assert_eq!(
        fs::read_to_string(paths.config).unwrap(),
        "model = \"gpt-5\"\n"
    );
}

#[test]
fn a_second_apply_keeps_the_original_baseline() {
    let root = TempDir::new().unwrap();
    let paths = crate::paths::AppPaths::isolated(root.path());
    fs::create_dir_all(paths.config.parent().unwrap()).unwrap();
    fs::write(
        &paths.config,
        "[desktop]\nappearanceTheme = \"light\"\nlocaleOverride = \"zh-CN\"\n",
    )
    .unwrap();
    let store = ConfigStore::new(paths.clone());
    let first = catalog::theme_by_id("tokyo-night").unwrap();
    let second = catalog::theme_by_id("dracula").unwrap();
    store.apply(&first, &first.id, false).unwrap();
    store.apply(&second, &second.id, false).unwrap();
    store.restore(false).unwrap();
    let restored = fs::read_to_string(paths.config).unwrap();
    assert!(restored.contains("appearanceTheme = \"light\""));
    assert!(restored.contains("localeOverride = \"zh-CN\""));
    assert!(!restored.contains("appearanceDarkChromeTheme"));
}

#[test]
fn checkpoint_restores_the_previous_applied_theme_and_state() {
    let temp = tempfile::tempdir().unwrap();
    let paths = AppPaths::isolated(temp.path());
    let store = ConfigStore::new(paths.clone());
    fs::create_dir_all(paths.config.parent().unwrap()).unwrap();
    fs::write(&paths.config, "model = \"gpt-5\"\n").unwrap();

    store
        .apply(
            &catalog::theme_by_id("codex-dark").unwrap(),
            "codex-dark",
            false,
        )
        .unwrap();
    let expected_config = fs::read(&paths.config).unwrap();
    let expected_state = fs::read(store.state_path()).unwrap();
    let checkpoint = store.checkpoint().unwrap();

    store
        .apply(
            &catalog::theme_by_id("github-light").unwrap(),
            "github-light",
            true,
        )
        .unwrap();
    store.rollback(checkpoint).unwrap();

    assert_eq!(fs::read(&paths.config).unwrap(), expected_config);
    assert_eq!(fs::read(store.state_path()).unwrap(), expected_state);
}

#[test]
fn legacy_swift_state_and_draft_are_migrated() {
    let root = TempDir::new().unwrap();
    let paths = crate::paths::AppPaths::isolated(root.path());
    fs::create_dir_all(&paths.support).unwrap();
    fs::write(
        paths.support.join("state.json"),
        r##"{
          "version": 2,
          "originalConfigExisted": true,
          "originalAppearance": {
            "values": {"appearanceTheme": "\"light\""},
            "chromeSections": {}
          },
          "selectedThemeID": "tokyo-night",
          "needsRestart": true,
          "appliedAt": "2026-07-23T00:00:00Z"
        }"##,
    )
    .unwrap();
    fs::write(
        paths.support.join("custom-theme.json"),
        r##"{
          "name": "旧草稿", "mode": "dark", "codeThemeID": "dracula",
          "accent": "#BD93F9", "ink": "#F8F8F2", "surface": "#282A36",
          "contrast": 62
        }"##,
    )
    .unwrap();
    let state = ConfigStore::new(paths).read_state().unwrap().unwrap();
    assert_eq!(state.selected_theme_id.as_deref(), Some("tokyo-night"));
    assert_eq!(
        state.baseline.items["appearanceTheme"].as_deref(),
        Some("[desktop]\nappearanceTheme = \"light\"\n")
    );
    let bootstrap = AppService::isolated(root.path()).bootstrap().unwrap();
    assert_eq!(bootstrap.custom_draft.code_theme_id, "dracula");
}

#[test]
fn legacy_v1_state_uses_the_original_config_backup() {
    let root = TempDir::new().unwrap();
    let paths = crate::paths::AppPaths::isolated(root.path());
    fs::create_dir_all(&paths.support).unwrap();
    fs::write(
        paths.support.join("state.json"),
        r#"{
          "version": 1,
          "originalConfigExisted": true,
          "selectedThemeID": "dracula",
          "needsRestart": false,
          "appliedAt": null
        }"#,
    )
    .unwrap();
    fs::write(
        paths.support.join("original-config.toml"),
        "[desktop]\nappearanceTheme = \"light\"\n",
    )
    .unwrap();
    let state = ConfigStore::new(paths).read_state().unwrap().unwrap();
    assert_eq!(
        state.baseline.items["appearanceTheme"].as_deref(),
        Some("[desktop]\nappearanceTheme = \"light\"\n")
    );
}

#[test]
fn invalid_toml_fails_without_creating_state() {
    let root = TempDir::new().unwrap();
    let paths = crate::paths::AppPaths::isolated(root.path());
    fs::create_dir_all(paths.config.parent().unwrap()).unwrap();
    fs::write(&paths.config, "[desktop\nappearanceTheme = true").unwrap();
    let store = ConfigStore::new(paths);
    let error = store
        .apply(
            &catalog::theme_by_id("codex-dark").unwrap(),
            "codex-dark",
            false,
        )
        .unwrap_err();
    assert!(matches!(error, AppError::InvalidConfig(_)));
    assert!(!store.state_path().exists());
}

#[test]
fn image_import_normalizes_and_rejects_tiny_files() {
    let root = TempDir::new().unwrap();
    let store = ImageStore::new(root.path());
    let valid_path = root.path().join("valid.png");
    let valid = ImageBuffer::from_pixel(320, 240, Rgba([20_u8, 180, 90, 255]));
    valid.save(&valid_path).unwrap();
    let imported = store.import(&valid_path).unwrap();
    assert!(imported.name.ends_with(".png"));
    assert!(store.resolve(Some(&imported.name)).is_some());
    assert!(imported.suggested_accent.is_some());
    assert!(store
        .data_url(Some(&imported.name))
        .unwrap()
        .unwrap()
        .starts_with("data:image/png;base64,"));

    let tiny_path = root.path().join("tiny.png");
    ImageBuffer::from_pixel(32, 32, Rgba([0_u8, 0, 0, 255]))
        .save(&tiny_path)
        .unwrap();
    assert!(matches!(
        store.import(&tiny_path),
        Err(AppError::InvalidImage(_))
    ));
}

#[test]
fn library_snapshots_background_and_validates_names() {
    let root = TempDir::new().unwrap();
    let images = ImageStore::new(root.path());
    let source = root.path().join("source.png");
    ImageBuffer::from_pixel(320, 240, Rgba([40_u8, 90, 210, 255]))
        .save(&source)
        .unwrap();
    let imported = images.import(&source).unwrap();
    let draft = CustomThemeDraft {
        name: "保存主题".into(),
        background_image_name: Some(imported.name.clone()),
        ..CustomThemeDraft::default()
    };
    let library = ThemeLibrary::new(root.path());
    library.save_custom(&draft).unwrap();
    let custom = library
        .items()
        .unwrap()
        .into_iter()
        .find(|item| item.kind == ThemeKind::Custom)
        .unwrap();
    assert_ne!(
        custom.custom_draft.as_ref().unwrap().background_image_name,
        Some(imported.name)
    );
    assert!(library.rename(&custom.id, "\n").is_err());
    library.delete(&custom.id).unwrap();
    assert!(library
        .items()
        .unwrap()
        .iter()
        .all(|item| item.kind == ThemeKind::BuiltIn));
}

#[test]
fn image_theme_application_fails_closed() {
    let root = TempDir::new().unwrap();
    let service = AppService::isolated(root.path());
    let source = root.path().join("source.png");
    ImageBuffer::from_pixel(320, 240, Rgba([120_u8, 80, 180, 255]))
        .save(&source)
        .unwrap();
    let data = service
        .import_background(&source, CustomThemeDraft::default())
        .unwrap();
    let error = service
        .apply(ApplyRequest {
            item_id: None,
            draft: Some(data.custom_draft),
        })
        .unwrap_err();
    assert!(matches!(error, AppError::BackgroundUnsupported(_)));
}
