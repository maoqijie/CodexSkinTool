import { LoaderCircle, Paintbrush, RotateCcw } from "lucide-react";

interface ActionBarProps {
  busy: boolean;
  canApply: boolean;
  canRestore: boolean;
  notice?: string;
  applyLabel?: string;
  onApply: () => void;
  onRestore: () => void;
}

export function ActionBar({ busy, canApply, canRestore, notice, applyLabel = "应用主题", onApply, onRestore }: ActionBarProps) {
  return (
    <footer className="action-bar">
      <span className="operation-notice" role="status">{notice}</span>
      {canRestore && <button className="button secondary" disabled={busy} onClick={onRestore}><RotateCcw size={15} />恢复原始外观</button>}
      <button className="button primary" disabled={busy || !canApply} onClick={onApply}>
        {busy ? <LoaderCircle className="spin" size={16} /> : <Paintbrush size={16} />}{busy ? "处理中" : applyLabel}
      </button>
    </footer>
  );
}
