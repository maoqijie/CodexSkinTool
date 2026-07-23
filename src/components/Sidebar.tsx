import { CircleHelp, MonitorCog, Palette, SlidersHorizontal } from "lucide-react";
import appIcon from "../assets/app-icon-ui.png";
import type { Section } from "../useAppModel";
import type { ServiceStatus } from "../contracts";

const navigation = [
  { id: "themes", label: "换肤", icon: Palette },
  { id: "editor", label: "自定义", icon: SlidersHorizontal },
  { id: "about", label: "关于", icon: CircleHelp },
] as const;

interface SidebarProps {
  section: Section;
  status: ServiceStatus;
  onNavigate: (section: Section) => void;
}

export function Sidebar({ section, status, onNavigate }: SidebarProps) {
  return (
    <aside className="sidebar">
      <div className="brand">
        <img className="brand-mark" src={appIcon} alt="" />
        <strong>CodexSkinTool</strong>
      </div>
      <nav className="navigation" aria-label="主导航">
        {navigation.map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            className={section === id ? "nav-item active" : "nav-item"}
            aria-label={label}
            onClick={() => onNavigate(id)}
          >
            <Icon size={17} /><span>{label}</span>
          </button>
        ))}
      </nav>
      <div className="app-status">
        <MonitorCog size={17} />
        <span>
          <strong>Codex Desktop</strong>
          <small>{status.app.isInstalled ? `${status.app.platformLabel} · ${status.app.isRunning ? "运行中" : "未运行"}` : `${status.app.platformLabel} · 未找到`}</small>
        </span>
        <i className={status.app.isInstalled ? "status-dot ready" : "status-dot"} aria-hidden="true" />
      </div>
    </aside>
  );
}
