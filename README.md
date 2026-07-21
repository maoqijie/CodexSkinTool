# CodexSkinTool

Codex Desktop 的原生 macOS 一键换肤助手。浏览真实界面预览，选择主题后一次点击即可安全更新 Codex 外观；随时可以恢复换肤前的配色。

> 非 OpenAI 官方项目。当前版本仅支持 macOS 15+，适配 Bundle ID 为 `com.openai.codex` 的 Codex Desktop。

## 功能

- 10 套内置主题：Codex、GitHub、Notion、Solarized、Tokyo Night、Rose Pine、Dracula、Everforest、Vercel 等。
- 自定义主题：名称、明暗模式、代码主题、强调色、文字色、背景色与对比度均可调整。
- 本地图片背景：支持点击选择或直接拖入 PNG、JPEG、HEIC、TIFF、WebP，可调整填充方式、透明度和模糊度。
- 关于界面：展示当前版本和作者“猫七街”，并从公开仓库检查新版本。
- 精简导航：侧栏只保留换肤、设置和关于，主题库与自定义编辑收纳到对应页面。
- 预览 Codex 侧栏、工作区、输入框、强调色和代码主题，无需反复试错。
- 一键应用并受控重启 Codex，避免运行中的 Codex 用内存设置覆盖新主题。
- 首次应用前保存外观基线；恢复时仅回滚工具管理的外观键，保留之后修改的其他 Codex 设置。
- 原子写入与 `0600` 文件权限；重复受管键会安全停止，不猜测修复。
- 按 Bundle ID 探测 `/Applications/ChatGPT.app`、`Codex.app` 及用户应用目录。
- 不修改 `ChatGPT.app`、`Codex.app`、`app.asar`、签名、账号、对话或项目文件。

## 安装

需要 macOS 15+ 和 Xcode Command Line Tools。

```bash
git clone https://github.com/maoqijie/CodexSkinTool.git
cd CodexSkinTool
./scripts/install-app.sh
```

应用会安装到 `~/Applications/CodexSkinTool.app` 并打开。仓库构建使用 ad-hoc 签名，没有 Apple Developer ID 公证；首次启动时 macOS 可能要求在“系统设置 > 隐私与安全性”中确认。

也可以只构建：

```bash
./scripts/build-app.sh
open output/CodexSkinTool.app
```

## 使用

1. 在左侧选择主题，右侧即时查看 Codex 界面预览。
2. 选择“自定义”可编辑配色，也可以导入一张本地背景图片。
3. 点击“一键应用”。如果 Codex 正在运行，确认受控重启。
4. 需要撤销时点击“恢复原始外观”。

重启可能丢失 Codex 中尚未发送的输入，因此应用会在关闭运行中的 Codex 前显示确认。项目、对话和账号不会被修改。

## 工作原理

OpenAI 的 Codex Desktop 设置支持基础主题、强调色、背景/前景色和 UI/代码字体。普通主题和无图自定义主题通过 `~/.codex/config.toml` 的 `[desktop]` 外观配置实现。

Codex 官方配置不支持图片。只有选择图片时，工具才会用 `127.0.0.1` 回环 CDP 启动一次独立 Codex 会话，在验证 `app://` 页面与 Codex DOM 标记后注入不可交互的图片层。它不修改或重签官方应用；同一用户的本地进程仍可能访问该临时调试端口，因此切回普通主题或恢复外观时会终止注入器并正常重启 Codex。Codex 更新可能改变页面结构，届时图片模式会验证失败并停止，而不是盲目注入。

写入流程：

```text
确认重启 -> 优雅退出 Codex -> 保存首次外观基线 -> 原子写入主题 -> 普通方式重开 Codex
```

恢复流程仅合并回以下受管键：

- `appearanceTheme`
- `appearanceLightCodeThemeId` / `appearanceDarkCodeThemeId`
- `appearanceLightChromeTheme` / `appearanceDarkChromeTheme`

工具状态、自定义主题和复制后的背景图片位于 `~/Library/Application Support/CodexSkinTool`，文件权限为 `0600`。完整安全说明见 [SECURITY.md](SECURITY.md)。

## 开发与验证

```bash
./scripts/test.sh
./scripts/build-app.sh
```

`CodexSkinCoreChecks` 覆盖 TOML 注释/未知键保留、多行主题替换、重复键拒绝、首次外观基线、重复换肤、换肤后其他设置合并恢复、CRLF 字节恢复、自定义主题清洗、图片解码和权限校验。`Tests/Fixtures/StrictConfig/config.toml` 可用于当前 Codex CLI 的严格配置解析：

```bash
CODEX_HOME="$PWD/Tests/Fixtures/StrictConfig" \
  /Applications/ChatGPT.app/Contents/Resources/codex --strict-config doctor --json
```

输出中的 `config.load` 应为 `ok`。隔离目录没有登录凭据，因此 doctor 总体状态可以是 `fail`。

## 设计取舍

- **KISS / YAGNI**：普通主题保持官方配置路径；只有用户明确选择图片时才启动临时 CDP，不引入主题商店或远程资源。
- **DRY**：主题 schema、TOML 编辑和恢复逻辑集中在 `CodexSkinCore`，界面只消费领域模型。
- **SOLID**：主题目录、配置存储、Codex 应用生命周期和 SwiftUI 状态分别负责单一边界。

## 资料与归属

- [OpenAI Codex Settings - Appearance](https://learn.chatgpt.com/docs/reference/settings#appearance)
- [Codex Dream Skin](https://github.com/aithink001/Codex-Dream-Skin-Themes)
- [Codex Theme Studio](https://github.com/983033995/Codex-Theme-Studio)
- [Codex-Skin](https://github.com/lixiaobaivv/Codex-Skin)

实现为独立 clean-room 代码，没有复制社区项目源码或主题素材。详见 [NOTICE.md](NOTICE.md)。

## License

[MIT](LICENSE)
