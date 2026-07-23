import { ChevronRight, Clock3, Folder, Inbox, Plus, Settings2, Sparkles } from "lucide-react";
import type { CustomThemeDraft, Theme } from "../contracts";

interface ThemePreviewProps {
  theme: Theme;
  draft?: CustomThemeDraft | null;
  backgroundUrl?: string | null;
}

export function ThemePreview({ theme, draft, backgroundUrl }: ThemePreviewProps) {
  const colors = theme.chromeTheme;
  const style = {
    "--preview-surface": colors.surface,
    "--preview-ink": colors.ink,
    "--preview-accent": colors.accent,
    "--preview-image": backgroundUrl ? `url(${backgroundUrl})` : "none",
    "--preview-opacity": String(draft?.backgroundOpacity ?? 0),
    "--preview-blur": `${(draft?.backgroundBlur ?? 0) / 2}px`,
    "--preview-brightness": String(draft?.backgroundBrightness ?? 1),
    "--preview-position": `${(draft?.backgroundFocusX ?? 0.5) * 100}% ${(draft?.backgroundFocusY ?? 0.5) * 100}%`,
    "--preview-fit": draft?.backgroundFit ?? "cover",
  } as React.CSSProperties;

  return (
    <div className="theme-preview" style={style} aria-label={`${theme.name} 界面预览`}>
      <div className="preview-image" />
      <div className="preview-sidebar">
        <div className="preview-brand"><Sparkles size={14} /> Codex</div>
        <PreviewItem icon={<Plus />} label="新建任务" active />
        <PreviewItem icon={<Inbox />} label="收件箱" />
        <PreviewItem icon={<Clock3 />} label="自动化" />
        <span className="preview-label">项目</span>
        <PreviewItem icon={<Folder />} label="CodexSkinTool" />
        <div className="preview-spacer" />
        <PreviewItem icon={<Settings2 />} label="设置" />
      </div>
      <div className="preview-workspace">
        <div className="preview-toolbar"><strong>新任务</strong><span>•••</span></div>
        <div className="preview-main">
          <div><h3>今天想构建什么？</h3><p>描述任务，Codex 会在你的项目中完成工作。</p></div>
          <div className="preview-composer">
            <span>让 Codex 优化这个项目的主题切换体验</span>
            <div><button aria-label="添加附件"><Plus size={13} /></button><small>本地</small><i><ChevronRight size={13} /></i></div>
          </div>
        </div>
      </div>
    </div>
  );
}

function PreviewItem({ icon, label, active = false }: { icon: React.ReactElement; label: string; active?: boolean }) {
  return <div className={active ? "preview-item selected" : "preview-item"}>{icon}<span>{label}</span></div>;
}
