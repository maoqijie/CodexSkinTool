import { useCallback, useEffect, useState } from "react";
import { confirm, open } from "@tauri-apps/plugin-dialog";
import { desktop } from "./api";
import type { BootstrapData, CustomThemeDraft } from "./contracts";
import { mockBootstrap } from "./mock";

export type Section = "themes" | "editor" | "about";

export function useAppModel() {
  const [data, setData] = useState<BootstrapData>();
  const [section, setSection] = useState<Section>("themes");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [draft, setDraft] = useState<CustomThemeDraft>();
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string>();
  const [error, setError] = useState<string>();

  const load = useCallback(async () => {
    try {
      const next = desktop.isTauri() ? await desktop.bootstrap() : mockBootstrap;
      setData(next);
      setDraft(next.customDraft);
      setSelectedId((current) => current ?? next.status.selectedThemeId ?? next.themes[0]?.id ?? null);
    } catch (cause) {
      setError(messageOf(cause));
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  const run = useCallback(async (operation: () => Promise<BootstrapData | { status: BootstrapData["status"]; message: string }>) => {
    setBusy(true); setError(undefined); setNotice(undefined);
    try {
      const result = await operation();
      if ("themes" in result) {
        setData(result); setDraft(result.customDraft);
      } else {
        setData((current) => current && ({ ...current, status: result.status }));
        setNotice(result.message);
      }
    } catch (cause) { setError(messageOf(cause)); }
    finally { setBusy(false); }
  }, []);

  const simulated = useCallback((message: string) => Promise.resolve({ ...mockBootstrap, customDraft: draft ?? mockBootstrap.customDraft }).then((next) => {
    setNotice(message); return next;
  }), [draft]);

  const confirmRestart = async () => {
    if (!data?.status.app.isRunning) return true;
    const message = "重启可能丢失 Codex 中尚未发送的输入。项目、对话和账号不会被修改。";
    try {
      return desktop.isTauri()
        ? await confirm(message, { title: "重启 Codex 并应用主题？", kind: "warning" })
        : window.confirm(`重启 Codex 并应用主题？\n\n${message}`);
    } catch (cause) {
      setError(messageOf(cause));
      return false;
    }
  };

  const deleteTheme = async (id: string) => {
    const item = data?.themes.find((theme) => theme.id === id);
    const name = item?.theme.name ?? "此主题";
    const message = item?.kind === "builtIn"
      ? `删除“${name}”后，可通过“恢复内置主题”找回。`
      : `删除“${name}”及其背景图片副本后无法撤销。`;
    try {
      const approved = desktop.isTauri()
        ? await confirm(message, { title: "确认删除主题？", kind: "warning" })
        : window.confirm(`确认删除主题？\n\n${message}`);
      if (approved) {
        await run(() => desktop.isTauri() ? desktop.deleteTheme(id) : simulated("主题已删除"));
      }
    } catch (cause) {
      setError(messageOf(cause));
    }
  };

  const applySelected = async () => {
    if (!await confirmRestart()) return;
    await run(() => desktop.isTauri()
      ? desktop.applyTheme({ itemId: selectedId ?? undefined })
      : Promise.resolve({ status: mockBootstrap.status, message: "主题预览完成（浏览器模式不写入配置）" }));
  };
  const applyDraft = async () => {
    if (!draft || !await confirmRestart()) return;
    await run(() => desktop.isTauri()
      ? desktop.applyTheme({ draft })
      : Promise.resolve({ status: mockBootstrap.status, message: "自定义主题预览完成（浏览器模式不写入配置）" }));
  };
  const restore = () => run(() => desktop.isTauri() ? desktop.restore() : simulated("已模拟恢复原始外观"));
  const saveDraft = () => draft && run(() => desktop.isTauri() ? desktop.saveDraft(draft) : simulated("草稿已保留"));
  const saveToLibrary = () => draft && run(() => desktop.isTauri() ? desktop.saveToLibrary(draft) : simulated("主题已加入资料库"));

  const chooseBackground = async () => {
    if (!draft || !desktop.isTauri()) return;
    const selected = await open({ multiple: false, directory: false, filters: [{ name: "图片", extensions: ["png", "jpg", "jpeg", "tiff", "webp"] }] });
    if (typeof selected === "string") await run(() => desktop.importBackground(selected, draft));
  };

  return {
    data, section, setSection, selectedId, setSelectedId, draft, setDraft,
    busy, notice, error, applySelected, applyDraft, restore, saveDraft, saveToLibrary,
    chooseBackground,
    removeBackground: () => draft && run(() => desktop.isTauri() ? desktop.removeBackground(draft) : simulated("背景图片已移除")),
    deleteTheme,
    renameTheme: (id: string, name: string) => run(() => desktop.isTauri() ? desktop.renameTheme(id, name) : simulated("主题已重命名")),
    restoreBuiltIns: () => run(() => desktop.isTauri() ? desktop.restoreBuiltIns() : simulated("内置主题已恢复")),
    clearError: () => setError(undefined),
  };
}

function messageOf(cause: unknown) {
  return cause instanceof Error ? cause.message : typeof cause === "string" ? cause : "操作失败，请稍后重试";
}
