import type { BootstrapData, Theme, ThemeLibraryItem } from "./contracts";

const definitions = [
  ["codex-light", "Codex 明亮", "干净克制的原生明亮风格", "light", "codex", "#0D7C66", "#17211F", "#F7FAF9"],
  ["github-light", "GitHub 明亮", "清晰中性的开发者工作台", "light", "github", "#0969DA", "#24292F", "#FFFFFF"],
  ["notion-paper", "Notion 纸白", "温和低对比的专注体验", "light", "notion", "#2383E2", "#37352F", "#FFFFFF"],
  ["solarized-light", "Solarized 明亮", "经典护眼配色与稳定层次", "light", "solarized", "#268BD2", "#586E75", "#FDF6E3"],
  ["codex-dark", "Codex 深色", "沉静克制的原生深色界面", "dark", "codex", "#10A37F", "#ECECF1", "#171717"],
  ["tokyo-night", "Tokyo Night", "冷静夜色与鲜明代码焦点", "dark", "tokyo-night", "#7AA2F7", "#C0CAF5", "#1A1B26"],
  ["rose-pine", "Rose Pine", "柔和玫瑰色调的低眩光主题", "dark", "rose-pine", "#C4A7E7", "#E0DEF4", "#191724"],
  ["dracula", "Dracula", "高辨识度的经典开发主题", "dark", "dracula", "#BD93F9", "#F8F8F2", "#282A36"],
  ["everforest", "Everforest", "自然绿色调的舒缓深色主题", "dark", "everforest", "#A7C080", "#D3C6AA", "#2D353B"],
  ["vercel-dark", "Vercel 黑", "高对比黑白与利落蓝色强调", "dark", "vercel", "#006EFE", "#EDEDED", "#000000"],
] as const;

function theme(definition: (typeof definitions)[number]): Theme {
  const [id, name, description, mode, codeThemeId, accent, ink, surface] = definition;
  return {
    id, name, description, mode, codeThemeId,
    chromeTheme: {
      accent, ink, surface, contrast: mode === "dark" ? 58 : 42,
      fonts: { code: "SFMono-Regular, Consolas, monospace", ui: "system-ui, sans-serif" },
      opaqueWindows: true,
      semanticColors: { diffAdded: "#32B47A", diffRemoved: "#E5484D", skill: accent },
    },
  };
}

const themes: ThemeLibraryItem[] = definitions.map((definition) => ({
  id: definition[0], kind: "builtIn", theme: theme(definition), customDraft: null, backgroundUrl: null,
}));

export const mockBootstrap: BootstrapData = {
  status: {
    selectedThemeId: "codex-dark", configExists: true, canRestore: true, needsRestart: false,
    app: {
      platform: "windows", platformLabel: "Windows", isInstalled: true,
      appPath: "C:\\Program Files\\OpenAI\\Codex\\Codex.exe", version: "1.0.0", isRunning: true,
    },
    backgroundSkin: { active: false, port: null },
  },
  themes,
  customDraft: {
    name: "我的主题", mode: "dark", codeThemeId: "codex", accent: "#10A37F",
    ink: "#F4F4F4", surface: "#171717", contrast: 55, backgroundImageName: null,
    backgroundOpacity: 0.28, backgroundBlur: 0, backgroundFit: "cover",
    backgroundBrightness: 1, backgroundFocusX: 0.5, backgroundFocusY: 0.5,
  },
  customBackgroundUrl: null,
  version: "1.2.0",
  repositoryUrl: "https://github.com/maoqijie/CodexSkinTool",
  supportedCodeThemeIds: ["codex", "github", "notion", "solarized", "tokyo-night", "rose-pine", "dracula", "everforest", "vercel"],
};
