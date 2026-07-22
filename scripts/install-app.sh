#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${1:-$HOME/Applications/CodexSkinTool.app}"

printf 'INFO: 安装 legacy macOS Swift 应用；当前 Tauri 应用请使用 Tauri 生成的安装包\n'
"$ROOT/scripts/build-app.sh" "$DESTINATION"
/usr/bin/open "$DESTINATION"
