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

图片背景不属于 Codex 的受支持外观配置。图片导入会完整解码、限制大小和尺寸，并转换成私有 PNG。应用图片主题时，工具先验证官方 Codex 签名，只允许 `127.0.0.1` 的 CDP listener，并保存 PID、启动时间、可执行路径和进程树归属。listener 无法回溯到本次启动的官方进程时会立即失败回滚。

helper 只接受 `/json/list` 返回的 `app://` page；WebSocket 必须使用 `ws`、本机 host、会话端口和 `/devtools/page/<target-id>`，且不得包含凭据、query 或 fragment。注入前要求 Codex 主界面、侧栏和 main role DOM 同时存在；注入后通过 computed style 验证图片、透明度、亮度、焦点和 `pointer-events: none`。私有 lease 被删除后 helper 自动退出，并持续轮询以处理 renderer 重载。

停止会话时，只结束 PID 与启动时间仍匹配、可执行路径仍位于已验证安装根、父链仍属于会话的进程；身份发生变化时拒绝结束未知 PID。Windows Store/AppX/MSIX 图片模式当前 fail closed，因为包激活需要额外 AUMID 身份与参数传递验证。

## Release artifacts

GitHub Actions 在 macOS 和 Windows 原生 runner 上构建 `.app`/`.dmg` 与 NSIS/MSI。CI 产物用于构建验证，默认不具备面向最终用户分发所需的 Apple Developer ID、公证或 Windows Authenticode 发布签名。正式发布必须在可信发布流程中签名，并在目标系统验证签名和安装行为。

## Reporting

请通过 GitHub 的 Private vulnerability reporting 报告漏洞。不要在公开 issue 中包含 API key、认证文件、私人对话或完整 `config.toml`。
