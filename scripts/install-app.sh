#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${1:-$HOME/Applications/CodexSkinTool.app}"

"$ROOT/scripts/build-app.sh" "$DESTINATION"
/usr/bin/open "$DESTINATION"
