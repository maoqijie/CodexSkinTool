#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

printf 'INFO: 运行 legacy macOS Swift 行为基准；跨平台验证请使用 node ./scripts/verify.mjs\n'
/usr/bin/swift run --package-path "$ROOT" CodexSkinCoreChecks
/usr/bin/swift build --package-path "$ROOT" -c release

printf 'PASS: CodexSkinTool legacy Swift baseline\n'
