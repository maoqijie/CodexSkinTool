import { useMemo, useState } from "react";
import { Moon, PanelLeft, RotateCcw, Sun } from "lucide-react";
import type { BootstrapData } from "../contracts";
import { ActionBar } from "../components/ActionBar";
import { ThemeCard } from "../components/ThemeCard";
import { ThemePreview } from "../components/ThemePreview";

type Filter = "all" | "custom" | "recent";

interface ThemesPageProps {
  data: BootstrapData;
  selectedId: string | null;
  busy: boolean;
  notice?: string;
  onSelect: (id: string) => void;
  onApply: () => void;
  onRestore: () => void;
  onDelete: (id: string) => void;
  onRename: (id: string, name: string) => void;
  onRestoreBuiltIns: () => void;
}

export function ThemesPage(props: ThemesPageProps) {
  const [filter, setFilter] = useState<Filter>("all");
  const selected = props.data.themes.find((item) => item.id === props.selectedId) ?? props.data.themes[0];
  const visible = useMemo(() => {
    if (filter === "custom") return props.data.themes.filter((item) => item.kind === "custom");
    if (filter === "recent") return props.data.themes.filter((item) => item.id === props.data.status.selectedThemeId);
    return props.data.themes;
  }, [filter, props.data]);

  const rename = (id: string, current: string) => {
    const next = window.prompt("主题名称", current)?.trim();
    if (next) props.onRename(id, next);
  };

  return (
    <div className="page-shell">
      <header className="page-header"><div><h1>换肤</h1><p>选择一套主题，先预览，再安全应用到 Codex Desktop。</p></div>
        <button className="button secondary" disabled={props.busy} onClick={props.onRestoreBuiltIns}><RotateCcw size={15} />恢复内置主题</button>
      </header>
      <main className="page-scroll themes-page">
        <div className="segmented" aria-label="主题筛选">
          {(["all", "custom", "recent"] as const).map((value) => <button key={value} className={filter === value ? "active" : ""} onClick={() => setFilter(value)}>{value === "all" ? "全部" : value === "custom" ? "我的" : "最近"}</button>)}
        </div>
        {visible.length ? <section className="theme-grid" aria-label="主题库">
          {visible.map((item) => <ThemeCard key={item.id} item={item} selected={item.id === selected?.id} active={item.id === props.data.status.selectedThemeId} onSelect={() => props.onSelect(item.id)} onRename={() => rename(item.id, item.theme.name)} onDelete={() => props.onDelete(item.id)} />)}
        </section> : <div className="empty-state">当前筛选下没有主题</div>}
        {selected && <section className="preview-section">
          <div className="section-heading"><h2>界面预览</h2><span>{selected.theme.name}</span></div>
          <ThemePreview theme={selected.theme} draft={selected.customDraft} backgroundUrl={selected.backgroundUrl} />
          <div className="theme-metadata">
            <Meta icon={selected.theme.mode === "dark" ? <Moon /> : <Sun />} label="外观模式" value={selected.theme.mode === "dark" ? "深色" : "浅色"} />
            <Meta icon={<PanelLeft />} label="代码主题" value={selected.theme.codeThemeId} />
            <Meta icon={<span className="accent-dot" style={{ background: selected.theme.chromeTheme.accent }} />} label="强调色" value={selected.theme.chromeTheme.accent} />
          </div>
        </section>}
      </main>
      <ActionBar busy={props.busy} canApply={props.data.status.app.isInstalled && Boolean(selected)} canRestore={props.data.status.canRestore} notice={props.notice} onApply={props.onApply} onRestore={props.onRestore} />
    </div>
  );
}

function Meta({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return <div className="meta-item"><span className="meta-icon">{icon}</span><span><small>{label}</small><strong>{value}</strong></span></div>;
}
