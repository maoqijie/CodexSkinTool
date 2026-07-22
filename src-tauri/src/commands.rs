use crate::error::AppError;
use crate::models::CustomThemeDraft;
use crate::service::{AppService, ApplyRequest, BootstrapData, OperationResult};
use std::path::PathBuf;
use std::sync::{Mutex, MutexGuard};

pub struct BackendState {
    gate: Mutex<()>,
}

impl BackendState {
    pub fn new() -> Self {
        Self {
            gate: Mutex::new(()),
        }
    }

    fn lock(&self) -> Result<MutexGuard<'_, ()>, AppError> {
        self.gate
            .lock()
            .map_err(|_| AppError::InvalidState("后端操作锁已损坏".into()))
    }
}

fn service() -> Result<AppService, AppError> {
    AppService::live()
}

#[tauri::command]
pub fn bootstrap(state: tauri::State<'_, BackendState>) -> Result<BootstrapData, AppError> {
    let _guard = state.lock()?;
    service()?.bootstrap()
}

#[tauri::command]
pub fn apply_theme(
    state: tauri::State<'_, BackendState>,
    request: ApplyRequest,
) -> Result<OperationResult, AppError> {
    let _guard = state.lock()?;
    service()?.apply(request)
}

#[tauri::command]
pub fn restore_theme(state: tauri::State<'_, BackendState>) -> Result<OperationResult, AppError> {
    let _guard = state.lock()?;
    service()?.restore()
}

#[tauri::command]
pub fn save_draft(
    state: tauri::State<'_, BackendState>,
    draft: CustomThemeDraft,
) -> Result<BootstrapData, AppError> {
    let _guard = state.lock()?;
    service()?.save_draft(draft)
}

#[tauri::command]
pub fn save_to_library(
    state: tauri::State<'_, BackendState>,
    draft: CustomThemeDraft,
) -> Result<BootstrapData, AppError> {
    let _guard = state.lock()?;
    service()?.save_to_library(draft)
}

#[tauri::command]
pub fn delete_theme(
    state: tauri::State<'_, BackendState>,
    item_id: String,
) -> Result<BootstrapData, AppError> {
    let _guard = state.lock()?;
    service()?.delete_theme(&item_id)
}

#[tauri::command]
pub fn rename_theme(
    state: tauri::State<'_, BackendState>,
    item_id: String,
    name: String,
) -> Result<BootstrapData, AppError> {
    let _guard = state.lock()?;
    service()?.rename_theme(&item_id, &name)
}

#[tauri::command]
pub fn restore_built_ins(state: tauri::State<'_, BackendState>) -> Result<BootstrapData, AppError> {
    let _guard = state.lock()?;
    service()?.restore_built_ins()
}

#[tauri::command]
pub fn import_background(
    state: tauri::State<'_, BackendState>,
    path: PathBuf,
    draft: CustomThemeDraft,
) -> Result<BootstrapData, AppError> {
    let _guard = state.lock()?;
    service()?.import_background(&path, draft)
}

#[tauri::command]
pub fn remove_background(
    state: tauri::State<'_, BackendState>,
    draft: CustomThemeDraft,
) -> Result<BootstrapData, AppError> {
    let _guard = state.lock()?;
    service()?.remove_background(draft)
}
