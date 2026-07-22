import { AlertTriangle, X } from "lucide-react";
import { Sidebar } from "./components/Sidebar";
import { AboutPage } from "./pages/AboutPage";
import { EditorPage } from "./pages/EditorPage";
import { ThemesPage } from "./pages/ThemesPage";
import { useAppModel } from "./useAppModel";

export default function App() {
  const model = useAppModel();
  if (!model.data || !model.draft) return <div className="loading-screen"><span className="loading-mark" />正在读取本地配置</div>;
  return (
    <div className="app-layout">
      <Sidebar section={model.section} status={model.data.status} onNavigate={model.setSection} />
      <section className="workspace">
        {model.error && <div className="error-banner" role="alert"><AlertTriangle size={16} /><span>{model.error}</span><button aria-label="关闭错误" onClick={model.clearError}><X size={15} /></button></div>}
        {model.section === "themes" && <ThemesPage data={model.data} selectedId={model.selectedId} busy={model.busy} notice={model.notice} onSelect={model.setSelectedId} onApply={model.applySelected} onRestore={model.restore} onDelete={model.deleteTheme} onRename={model.renameTheme} onRestoreBuiltIns={model.restoreBuiltIns} />}
        {model.section === "editor" && <EditorPage data={model.data} draft={model.draft} busy={model.busy} notice={model.notice} onChange={model.setDraft} onApply={model.applyDraft} onRestore={model.restore} onSaveDraft={model.saveDraft} onSaveToLibrary={model.saveToLibrary} onChooseBackground={model.chooseBackground} onRemoveBackground={model.removeBackground} />}
        {model.section === "about" && <AboutPage data={model.data} />}
      </section>
    </div>
  );
}
