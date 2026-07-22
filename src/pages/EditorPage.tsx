import { ImagePlus, Save, Trash2 } from "lucide-react";
import type { BootstrapData, CustomThemeDraft } from "../contracts";
import { ActionBar } from "../components/ActionBar";
import { ThemePreview } from "../components/ThemePreview";

interface EditorPageProps {
  data: BootstrapData;
  draft: CustomThemeDraft;
  busy: boolean;
  notice?: string;
  onChange: (draft: CustomThemeDraft) => void;
  onApply: () => void;
  onRestore: () => void;
  onSaveDraft: () => void;
  onSaveToLibrary: () => void;
  onChooseBackground: () => void;
  onRemoveBackground: () => void;
}

export function EditorPage(props: EditorPageProps) {
  const update = <K extends keyof CustomThemeDraft>(key: K, value: CustomThemeDraft[K]) => props.onChange({ ...props.draft, [key]: value });
  const theme = toTheme(props.draft);
  return (
    <div className="page-shell">
      <header className="page-header"><div><h1>自定义</h1><p>调整颜色、代码主题和本地背景，预览会即时更新。</p></div>
        <button className="button secondary" disabled={props.busy} onClick={props.onSaveDraft}><Save size={15} />保存草稿</button>
      </header>
      <main className="page-scroll editor-page">
        <ThemePreview theme={theme} draft={props.draft} backgroundUrl={props.data.customBackgroundUrl} />
        <section className="editor-panel">
          <h2>主题设置</h2>
          <div className="form-grid three">
            <Field label="名称"><input value={props.draft.name} maxLength={40} onChange={(event) => update("name", event.target.value)} /></Field>
            <Field label="外观"><div className="segmented compact"><button className={props.draft.mode === "light" ? "active" : ""} onClick={() => update("mode", "light")}>浅色</button><button className={props.draft.mode === "dark" ? "active" : ""} onClick={() => update("mode", "dark")}>深色</button></div></Field>
            <Field label="代码主题"><select value={props.draft.codeThemeId} onChange={(event) => update("codeThemeId", event.target.value)}>{props.data.supportedCodeThemeIds.map((id) => <option key={id}>{id}</option>)}</select></Field>
          </div>
          <div className="form-grid four colors-row">
            <ColorField label="强调色" value={props.draft.accent} onChange={(value) => update("accent", value)} />
            <ColorField label="文字色" value={props.draft.ink} onChange={(value) => update("ink", value)} />
            <ColorField label="背景色" value={props.draft.surface} onChange={(value) => update("surface", value)} />
            <RangeField label={`对比度 ${props.draft.contrast}`} min={0} max={100} value={props.draft.contrast} onChange={(value) => update("contrast", value)} />
          </div>
        </section>
        <section className="editor-panel">
          <div className="section-heading"><h2>背景图片</h2><span>PNG、JPEG、TIFF 或 WebP，最大 16 MB</span></div>
          <div className="background-picker">
            <ImagePlus size={22} /><span><strong>{props.draft.backgroundImageName ?? "未选择本地图片"}</strong><small>图片仅保存在本机应用数据目录</small></span>
            {props.draft.backgroundImageName && <button className="icon-button danger" title="移除图片" onClick={props.onRemoveBackground}><Trash2 size={15} /></button>}
            <button className="button secondary" onClick={props.onChooseBackground}>{props.draft.backgroundImageName ? "更换图片" : "选择图片"}</button>
          </div>
          {props.draft.backgroundImageName && <div className="form-grid three background-controls">
            <Field label="显示方式"><select value={props.draft.backgroundFit} onChange={(event) => update("backgroundFit", event.target.value as CustomThemeDraft["backgroundFit"])}><option value="cover">填充</option><option value="contain">完整显示</option></select></Field>
            <RangeField label={`透明度 ${Math.round(props.draft.backgroundOpacity * 100)}%`} min={8} max={85} value={props.draft.backgroundOpacity * 100} onChange={(value) => update("backgroundOpacity", value / 100)} />
            <RangeField label={`模糊 ${props.draft.backgroundBlur}`} min={0} max={24} value={props.draft.backgroundBlur} onChange={(value) => update("backgroundBlur", value)} />
          </div>}
        </section>
        <button className="button library-button" disabled={props.busy} onClick={props.onSaveToLibrary}><Save size={15} />保存到我的主题</button>
      </main>
      <ActionBar busy={props.busy} canApply={props.data.status.app.isInstalled} canRestore={props.data.status.canRestore} notice={props.notice} applyLabel="应用当前配置" onApply={props.onApply} onRestore={props.onRestore} />
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) { return <label className="field"><span>{label}</span>{children}</label>; }
function ColorField({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) { return <Field label={label}><div className="color-input"><input type="color" value={value} aria-label={label} onChange={(event) => onChange(event.target.value.toUpperCase())} /><code>{value}</code></div></Field>; }
function RangeField({ label, min, max, value, onChange }: { label: string; min: number; max: number; value: number; onChange: (value: number) => void }) { return <Field label={label}><input type="range" min={min} max={max} value={value} onChange={(event) => onChange(Number(event.target.value))} /></Field>; }
function toTheme(draft: CustomThemeDraft) { return { id: "custom", name: draft.name || "我的主题", description: "自定义配色与代码主题", mode: draft.mode, codeThemeId: draft.codeThemeId, chromeTheme: { accent: draft.accent, ink: draft.ink, surface: draft.surface, contrast: draft.contrast, fonts: { code: null, ui: null }, opaqueWindows: true, semanticColors: { diffAdded: "#32B47A", diffRemoved: "#E5484D", skill: draft.accent } } }; }
