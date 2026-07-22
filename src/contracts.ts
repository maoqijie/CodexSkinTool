export type ThemeMode = "light" | "dark";
export type ThemeKind = "builtIn" | "custom";
export type BackgroundFit = "cover" | "contain";

export interface ThemeFonts {
  code: string | null;
  ui: string | null;
}

export interface ThemeSemanticColors {
  diffAdded: string;
  diffRemoved: string;
  skill: string;
}

export interface ChromeTheme {
  accent: string;
  ink: string;
  surface: string;
  contrast: number;
  fonts: ThemeFonts;
  opaqueWindows: boolean;
  semanticColors: ThemeSemanticColors;
}

export interface Theme {
  id: string;
  name: string;
  description: string;
  mode: ThemeMode;
  codeThemeId: string;
  chromeTheme: ChromeTheme;
}

export interface CustomThemeDraft {
  name: string;
  mode: ThemeMode;
  codeThemeId: string;
  accent: string;
  ink: string;
  surface: string;
  contrast: number;
  backgroundImageName: string | null;
  backgroundOpacity: number;
  backgroundBlur: number;
  backgroundFit: BackgroundFit;
  backgroundBrightness: number;
  backgroundFocusX: number;
  backgroundFocusY: number;
}

export interface ThemeLibraryItem {
  id: string;
  kind: ThemeKind;
  theme: Theme;
  customDraft: CustomThemeDraft | null;
  backgroundUrl: string | null;
}

export interface AppStatus {
  platform: "macos" | "windows" | "other";
  platformLabel: string;
  isInstalled: boolean;
  appPath: string | null;
  version: string | null;
  isRunning: boolean;
}

export interface BackgroundSkinStatus {
  active: boolean;
  port: number | null;
}

export interface ServiceStatus {
  selectedThemeId: string | null;
  configExists: boolean;
  canRestore: boolean;
  needsRestart: boolean;
  app: AppStatus;
  backgroundSkin: BackgroundSkinStatus;
}

export interface BootstrapData {
  status: ServiceStatus;
  themes: ThemeLibraryItem[];
  customDraft: CustomThemeDraft;
  customBackgroundUrl: string | null;
  version: string;
  repositoryUrl: string;
  supportedCodeThemeIds: string[];
}

export interface ApplyRequest {
  itemId?: string;
  draft?: CustomThemeDraft;
}

export interface OperationResult {
  status: ServiceStatus;
  message: string;
}
