import { ExternalLink, Github, MonitorCog, ShieldCheck } from "lucide-react";
import type { BootstrapData } from "../contracts";

export function AboutPage({ data }: { data: BootstrapData }) {
  return <div className="page-shell"><header className="page-header"><div><h1>关于</h1><p>跨平台的 Codex Desktop 本地换肤工具。</p></div></header>
    <main className="page-scroll about-page">
      <div className="about-identity"><div className="about-icon">C</div><h2>CodexSkinTool</h2><p>版本 {data.version} · 作者 猫七街</p></div>
      <div className="about-facts">
        <div><MonitorCog /><span><strong>同一套工程</strong><small>Tauri 2、React 与 Rust 同时构建 macOS 和 Windows。</small></span></div>
        <div><ShieldCheck /><span><strong>本地与可恢复</strong><small>只管理 Codex 外观键，不修改应用文件、账号或项目。</small></span></div>
      </div>
      <a className="repository-link" href={data.repositoryUrl} target="_blank" rel="noreferrer"><Github size={18} />GitHub 开源仓库<ExternalLink size={14} /></a>
    </main>
  </div>;
}
