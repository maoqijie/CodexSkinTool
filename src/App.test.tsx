import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import App from "./App";

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

  it("updates the preview when another theme is selected", async () => {
    render(<App />);
    const library = await screen.findByRole("region", { name: "主题库" });

    fireEvent.click(within(library).getByRole("button", { name: /^GitHub 明亮/ }));

    expect(within(library).getByRole("button", { name: /^GitHub 明亮/ })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByLabelText("GitHub 明亮 界面预览")).toBeInTheDocument();
    expect(screen.getByText("github")).toBeInTheDocument();
    expect(screen.getByText("#0969DA")).toBeInTheDocument();
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
});
