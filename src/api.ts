import { invoke } from "@tauri-apps/api/core";
import type {
  ApplyRequest,
  BootstrapData,
  CustomThemeDraft,
  OperationResult,
  ThemeLibraryItem,
} from "./contracts";

const isTauri = () => "__TAURI_INTERNALS__" in window;

export const desktop = {
  isTauri,
  bootstrap: () => invoke<BootstrapData>("bootstrap"),
  applyTheme: (request: ApplyRequest) => invoke<OperationResult>("apply_theme", { request }),
  restore: () => invoke<OperationResult>("restore_theme"),
  saveDraft: (draft: CustomThemeDraft) => invoke<BootstrapData>("save_draft", { draft }),
  saveToLibrary: (draft: CustomThemeDraft) =>
    invoke<BootstrapData>("save_to_library", { draft }),
  deleteTheme: (itemId: string) => invoke<BootstrapData>("delete_theme", { itemId }),
  renameTheme: (itemId: string, name: string) =>
    invoke<BootstrapData>("rename_theme", { itemId, name }),
  restoreBuiltIns: () => invoke<BootstrapData>("restore_built_ins"),
  importBackground: (path: string, draft: CustomThemeDraft) =>
    invoke<BootstrapData>("import_background", { path, draft }),
  removeBackground: (draft: CustomThemeDraft) =>
    invoke<BootstrapData>("remove_background", { draft }),
  refreshStatus: () => invoke<BootstrapData>("bootstrap"),
  themeById: (data: BootstrapData, id: string | null): ThemeLibraryItem | undefined =>
    data.themes.find((item) => item.id === id),
};
