import { Check, Pencil, Trash2 } from "lucide-react";
import type { ThemeLibraryItem } from "../contracts";

interface ThemeCardProps {
  item: ThemeLibraryItem;
  selected: boolean;
  active: boolean;
  onSelect: () => void;
  onRename: () => void;
  onDelete: () => void;
}

export function ThemeCard({ item, selected, active, onSelect, onRename, onDelete }: ThemeCardProps) {
  return (
    <article className={selected ? "theme-card selected" : "theme-card"}>
      <button className="theme-select" onClick={onSelect} aria-pressed={selected}>
        <span className="swatches" aria-hidden="true">
          {[item.theme.chromeTheme.accent, item.theme.chromeTheme.surface, item.theme.chromeTheme.ink].map((color) => <i key={color} style={{ background: color }} />)}
        </span>
        <strong>{item.theme.name}</strong>
        <small>{item.theme.description}</small>
        {active && <span className="active-theme"><Check size={12} />当前</span>}
      </button>
      <span className="card-tools">
        <button title="重命名" aria-label={`重命名 ${item.theme.name}`} onClick={onRename}><Pencil size={14} /></button>
        <button title="删除" aria-label={`删除 ${item.theme.name}`} onClick={onDelete}><Trash2 size={14} /></button>
      </span>
    </article>
  );
}
