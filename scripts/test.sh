#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

/usr/bin/swift run --package-path "$ROOT" CodexSkinCoreChecks
/usr/bin/swift build --package-path "$ROOT" -c release

printf 'PASS: CodexSkinTool\n'
