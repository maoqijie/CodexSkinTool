import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import App from "./App";
import { EditorPage } from "./pages/EditorPage";
import { mockBootstrap } from "./mock";

describe("CodexSkinTool", () => {
  it("renders the theme library and current theme preview", async () => {
    render(<App />);

    expect(await screen.findByRole("heading", { name: "换肤" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "主题库" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /^Codex 深色/ })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByLabelText("Codex 深色 界面预览")).toBeInTheDocument();
  });

  it("navigates to the custom theme editor", async () => {
    render(<App />);
    await screen.findByRole("heading", { name: "换肤" });

    fireEvent.click(screen.getByRole("button", { name: "自定义" }));

    expect(screen.getByRole("heading", { name: "自定义" })).toBeInTheDocument();
    expect(screen.getByRole("textbox", { name: "名称" })).toHaveValue("我的主题");
    expect(screen.getByRole("button", { name: "应用当前配置" })).toBeEnabled();
  });

  it("keeps the interface free of redundant explanatory copy", async () => {
    render(<App />);
    await screen.findByRole("heading", { name: "换肤" });

    expect(screen.queryByText("跨平台主题管理")).not.toBeInTheDocument();
    expect(screen.queryByText("选择一套主题，先预览，再安全应用到 Codex Desktop。")).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "自定义" }));
    expect(screen.queryByText("调整颜色、代码主题和本地背景，预览会即时更新。")).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "关于" }));
    expect(screen.getByRole("img", { name: "CodexSkinTool 图标" })).toBeInTheDocument();
    expect(screen.queryByText("跨平台的 Codex Desktop 本地换肤工具。")).not.toBeInTheDocument();
    expect(screen.queryByText("同一套工程")).not.toBeInTheDocument();
    expect(screen.queryByText("本地与可恢复")).not.toBeInTheDocument();
  });

  it("updates the preview when another theme is selected", async () => {
    render(<App />);
    const library = await screen.findByRole("region", { name: "主题库" });

    fireEvent.click(within(library).getByRole("button", { name: /^GitHub 明亮/ }));

    expect(within(library).getByRole("button", { name: /^GitHub 明亮/ })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByLabelText("GitHub 明亮 界面预览")).toBeInTheDocument();
    expect(screen.getByText("github")).toBeInTheDocument();
    expect(screen.getByText("#0969DA")).toBeInTheDocument();
  });

  it("offers rename for built-in themes and confirms before deletion", async () => {
    const renamePrompt = vi.spyOn(window, "prompt").mockReturnValue(null);
    const deleteConfirm = vi.spyOn(window, "confirm").mockReturnValueOnce(false).mockReturnValueOnce(true);
    render(<App />);
    await screen.findByRole("region", { name: "主题库" });

    fireEvent.click(screen.getByRole("button", { name: "重命名 Codex 明亮" }));
    expect(renamePrompt).toHaveBeenCalledWith("主题名称", "Codex 明亮");

    fireEvent.click(screen.getByRole("button", { name: "删除 Codex 明亮" }));
    expect(deleteConfirm).toHaveBeenCalledWith(expect.stringContaining("删除“Codex 明亮”"));
    expect(screen.queryByText("主题已删除")).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "删除 Codex 明亮" }));
    expect(await screen.findByText("主题已删除")).toBeInTheDocument();
    expect(deleteConfirm).toHaveBeenCalledTimes(2);

    renamePrompt.mockRestore();
    deleteConfirm.mockRestore();
  });

  it("requires confirmation before restarting a running Codex instance", async () => {
    const confirmRestart = vi.spyOn(window, "confirm").mockReturnValue(false);
    render(<App />);
    await screen.findByRole("heading", { name: "换肤" });

    fireEvent.click(screen.getByRole("button", { name: "应用主题" }));

    await waitFor(() => expect(confirmRestart).toHaveBeenCalledOnce());
    expect(screen.queryByText("主题预览完成（浏览器模式不写入配置）")).not.toBeInTheDocument();
    confirmRestart.mockRestore();
  });

  it("edits background brightness and focus with platform-compatible ranges", () => {
    const onChange = vi.fn();
    const draft = {
      ...mockBootstrap.customDraft,
      name: "带图主题",
      backgroundImageName: "background.png",
      backgroundOpacity: 0.4,
      backgroundBlur: 8,
      backgroundFit: "contain" as const,
      backgroundBrightness: 0.85,
      backgroundFocusX: 0.3,
      backgroundFocusY: 0.7,
    };

    render(<EditorPage data={{ ...mockBootstrap, customDraft: draft, customBackgroundUrl: "data:image/png;base64,AA==" }} draft={draft} busy={false} onChange={onChange} onApply={vi.fn()} onRestore={vi.fn()} onSaveDraft={vi.fn()} onSaveToLibrary={vi.fn()} onChooseBackground={vi.fn()} onRemoveBackground={vi.fn()} />);

    const brightness = screen.getByRole("slider", { name: "亮度 85%" });
    const focusX = screen.getByRole("slider", { name: "水平焦点 30%" });
    const focusY = screen.getByRole("slider", { name: "垂直焦点 70%" });
    expect(brightness).toHaveAttribute("min", "0.45");
    expect(brightness).toHaveAttribute("max", "1.25");
    expect(brightness).toHaveAttribute("step", "0.05");
    expect(focusX).toHaveAttribute("min", "0");
    expect(focusX).toHaveAttribute("max", "1");
    expect(focusX).toHaveAttribute("step", "0.01");
    expect(focusY).toHaveAttribute("min", "0");
    expect(focusY).toHaveAttribute("max", "1");
    expect(focusY).toHaveAttribute("step", "0.01");

    fireEvent.change(brightness, { target: { value: "1.15" } });
    expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ backgroundBrightness: 1.15 }));
    fireEvent.change(focusX, { target: { value: "0.25" } });
    expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ backgroundFocusX: 0.25 }));
    fireEvent.change(focusY, { target: { value: "0.75" } });
    expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ backgroundFocusY: 0.75 }));

    const preview = screen.getByLabelText("带图主题 界面预览");
    expect(preview.style.getPropertyValue("--preview-opacity")).toBe("0.4");
    expect(preview.style.getPropertyValue("--preview-blur")).toBe("4px");
    expect(preview.style.getPropertyValue("--preview-brightness")).toBe("0.85");
    expect(preview.style.getPropertyValue("--preview-position")).toBe("30% 70%");
    expect(preview.style.getPropertyValue("--preview-fit")).toBe("contain");
  });
});
