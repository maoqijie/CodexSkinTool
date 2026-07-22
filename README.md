# CodexSkinTool

Codex Desktop 的跨平台换肤工具。项目使用 Tauri 2、React/TypeScript 和 Rust，macOS 与 Windows 共用同一套界面、主题模型、配置编辑和恢复逻辑；平台差异仅保留在应用发现、签名验证、进程控制和文件权限边界。

> 非 OpenAI 官方项目。当前跨平台版本为 `1.1.0`，支持 macOS 和 Windows 上的 Codex Desktop。

## 功能

- 内置主题、自定义主题资料库、筛选、重命名和删除。
- 自定义明暗模式、代码主题、强调色、文字色、背景色和对比度。
- 在应用前预览 Codex 侧栏、工作区、输入框和代码主题。
- 一键应用普通主题；Codex 正在运行时仅重启经过身份验证的官方进程。
- 首次应用时保存五个受管外观键的基线；恢复时保留其他 Codex 配置。
- 原子写入本地状态和 `~/.codex/config.toml`，macOS 使用 `0600`，Windows 使用仅当前用户、SYSTEM 和管理员可访问的 ACL。
- 兼容旧 Swift 版本的 v1/v2 状态和自定义主题草稿。

## 当前限制

普通主题和无图片自定义主题已接入跨平台实现。背景图片可以导入、规范化、预览并保存到资料库，但当前 Tauri 版本不会把图片注入 Codex：跨平台 CDP 进程身份验证尚未完成，应用图片主题会明确报错并停止，不会降级为未经验证的注入。

Windows 安装发现覆盖常见的普通安装目录和 AppX/MSIX 包。发布包可由 CI 生成，但官方 Codex 的实际安装路径、进程树和 Authenticode 行为仍应在目标 Windows 版本上做一次真机验收。

## 环境要求

通用依赖：

- Node.js 22
- Rust stable，包含 `rustfmt` 和 `clippy`
- 已安装 Codex Desktop

macOS 还需要 Xcode Command Line Tools。Windows 还需要 Microsoft C++ Build Tools 和 WebView2 Runtime；安装 Visual Studio Build Tools 时选择“使用 C++ 的桌面开发”。

## 开发

```bash
git clone https://github.com/maoqijie/CodexSkinTool.git
cd CodexSkinTool
npm ci
npm run tauri -- dev
```

`npm run dev` 仅启动浏览器 mock 界面，适合 UI 开发；配置写入、应用发现和进程控制必须通过 `npm run tauri -- dev` 验证。

## 验证

macOS 和 Windows 使用同一个验证入口：

```bash
node ./scripts/verify.mjs
```

它依次执行前端测试与生产构建，以及 Rust 的格式、编译、Clippy 和测试检查。也可以单独运行：

```bash
npm run test
npm run build
cargo fmt --manifest-path src-tauri/Cargo.toml -- --check
cargo check --manifest-path src-tauri/Cargo.toml --all-targets
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path src-tauri/Cargo.toml
```

## 打包

Tauri 桌面安装包必须在对应操作系统上构建，不能用 macOS 构建最终 Windows 安装包，反之亦然。

macOS：

```bash
npm run tauri -- build --bundles app,dmg
```

输出位于 `src-tauri/target/release/bundle/macos/` 和 `src-tauri/target/release/bundle/dmg/`。

Windows PowerShell：

```powershell
npm run tauri -- build --bundles nsis,msi
```

输出位于 `src-tauri/target/release/bundle/nsis/` 和 `src-tauri/target/release/bundle/msi/`。仓库 CI 会在 `macos-15` 与 `windows-2025` 上运行完整验证并上传未签名构建产物；正式分发仍需配置 Apple Developer ID、公证和 Windows 代码签名证书。

## 工作原理

普通主题通过 `~/.codex/config.toml` 的 `[desktop]` 外观配置实现。工具仅管理以下键：

- `appearanceTheme`
- `appearanceLightCodeThemeId`
- `appearanceDarkCodeThemeId`
- `appearanceLightChromeTheme`
- `appearanceDarkChromeTheme`

写入流程：

```text
保存首次外观基线 -> 原子写入主题 -> 如正在运行则验证官方 Codex -> 结束匹配路径的进程 -> 重开 Codex
```

身份验证或重启失败时，工具会恢复本次写入的受管外观键。macOS 通过 Bundle ID、Team ID 和代码签名验证官方应用；Windows 通过安装位置发现，并在重启前验证可执行文件的 Authenticode 签名与 OpenAI 发行者。完整边界见 [SECURITY.md](SECURITY.md)。

## 迁移期 Swift 基准

根目录的 `Package.swift`、`Sources/`、`Tests/` 以及 `scripts/test.sh`、`scripts/build-app.sh`、`scripts/install-app.sh` 是旧版 macOS SwiftUI 实现，仅作为迁移期行为基准和回归对照，不再是跨平台产品的开发或发布入口。

在 macOS 上可运行旧基准：

```bash
./scripts/test.sh
```

CI 会继续执行这组测试，直到 Tauri/Rust 覆盖相同行为后再单独移除。`scripts/build-app.sh` 生成的是 legacy Swift 应用，不代表当前 Tauri 发布包。

## 工程边界

- **KISS / YAGNI**：一套 React 界面和 Rust 领域层服务两个桌面平台；图片注入在身份边界完成前保持 fail-closed。
- **DRY**：主题 schema、TOML 编辑、恢复和旧状态迁移集中在 Rust，不在平台实现中复制。
- **SOLID**：共享领域服务依赖窄的平台边界；应用发现、原子文件操作和路径解析各自承担单一职责。

## 资料与归属

- [OpenAI Codex Settings - Appearance](https://learn.chatgpt.com/docs/reference/settings#appearance)
- [Codex Dream Skin](https://github.com/aithink001/Codex-Dream-Skin-Themes)
- [Codex Theme Studio](https://github.com/983033995/Codex-Theme-Studio)
- [Codex-Skin](https://github.com/lixiaobaivv/Codex-Skin)

实现为独立 clean-room 代码，没有复制社区项目源码或主题素材。详见 [NOTICE.md](NOTICE.md)。

## License

[MIT](LICENSE)
