import { ExternalLink, Github } from "lucide-react";
import type { BootstrapData } from "../contracts";

export function AboutPage({ data }: { data: BootstrapData }) {
  return <div className="page-shell"><header className="page-header"><h1>关于</h1></header>
    <main className="page-scroll about-page">
      <div className="about-identity"><div className="about-icon">C</div><h2>CodexSkinTool</h2><p>版本 {data.version} · 作者 猫七街</p></div>
      <a className="repository-link" href={data.repositoryUrl} target="_blank" rel="noreferrer"><Github size={18} />GitHub 开源仓库<ExternalLink size={14} /></a>
    </main>
  </div>;
}
