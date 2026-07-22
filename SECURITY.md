# Security

## Safety boundary

CodexSkinTool 仅编辑用户 `~/.codex/config.toml` 中五个受管外观键：

- `appearanceTheme`
- `appearanceLightCodeThemeId`
- `appearanceDarkCodeThemeId`
- `appearanceLightChromeTheme`
- `appearanceDarkChromeTheme`

它不会修改 Codex/ChatGPT 应用包、`app.asar`、签名、账号、对话、项目、凭据或服务商配置。恢复操作只合并回受管键的首次基线，保留之后由用户或其他工具修改的无关设置。无效 TOML、未知状态版本和无法安全恢复的状态会直接报错。

## Local data and file writes

主题状态、自定义草稿、资料库和导入图片保存在操作系统返回的当前用户本地数据目录下的 `CodexSkinTool` 目录。旧 Swift v1/v2 状态只迁移已知字段；未知版本不会猜测转换。

写入使用同目录临时文件、同步和原子替换。macOS/Unix 创建文件时使用 `0600`；Windows 移除继承 ACL，仅向当前用户、SYSTEM 和本机管理员授予完全控制。工具不会把完整 Codex 配置复制到自己的状态文件。

## Codex application identity

CodexSkinTool 只控制与已发现安装的规范化可执行路径完全匹配的进程，不按模糊进程名结束其他应用。

在 macOS 上，发现阶段要求 Bundle ID 为 `com.openai.codex`；重启前通过 `codesign` 验证 Apple 信任链、Bundle ID 和预期 Team ID。在 Windows 上，发现阶段覆盖受限的普通安装目录和 OpenAI AppX/MSIX 包；重启前通过 PowerShell `Get-AuthenticodeSignature` 要求签名状态为 `Valid` 且证书主体发行组织为 OpenAI。任何验证失败都会停止进程控制。

## Image backgrounds

图片背景不属于 Codex 的受支持外观配置。当前 Tauri 版本只允许导入、完整解码、限制大小和尺寸、转换为私有 PNG，以及在 CodexSkinTool 内预览或保存。应用包含图片的草稿或资料库主题时会 fail closed，并返回“跨平台 CDP 进程身份验证尚未完成”；它不会开启调试端口或执行未经验证的注入。

旧 Swift 实现包含 macOS 专用 CDP 注入器，但它仅作为 legacy 行为基准保留，不属于当前 Tauri 发布链。恢复这项能力前，需要在 macOS 和 Windows 上完成调试端点、页面身份、进程归属和生命周期的联合验证。

## Release artifacts

GitHub Actions 在 macOS 和 Windows 原生 runner 上构建 `.app`/`.dmg` 与 NSIS/MSI。CI 产物用于构建验证，默认不具备面向最终用户分发所需的 Apple Developer ID、公证或 Windows Authenticode 发布签名。正式发布必须在可信发布流程中签名，并在目标系统验证签名和安装行为。

## Reporting

请通过 GitHub 的 Private vulnerability reporting 报告漏洞。不要在公开 issue 中包含 API key、认证文件、私人对话或完整 `config.toml`。
