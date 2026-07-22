#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/bin/tr -d '\r\n' < "$ROOT/VERSION")"
OUTPUT="${1:-$ROOT/output/CodexSkinTool.app}"

printf 'INFO: 构建 legacy macOS Swift 应用；当前 Tauri 应用请使用 npm run tauri -- build\n'
if [ "$(/usr/bin/uname -s)" != "Darwin" ]; then
    printf 'Legacy CodexSkinTool can only be bundled on macOS.\n' >&2
    exit 1
fi

"$ROOT/scripts/test.sh"
BIN_DIR="$(/usr/bin/swift build --package-path "$ROOT" -c release --show-bin-path)"
TEMP_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/codex-skin-tool.XXXXXX")"
trap '/bin/rm -rf "$TEMP_ROOT"' EXIT

APP="$TEMP_ROOT/CodexSkinTool.app"
CONTENTS="$APP/Contents"
RESOURCES="$CONTENTS/Resources"
ICONSET="$TEMP_ROOT/AppIcon.iconset"
/bin/mkdir -p "$CONTENTS/MacOS" "$RESOURCES" "$ICONSET"
/bin/cp "$BIN_DIR/CodexSkinTool" "$CONTENTS/MacOS/CodexSkinTool"
/bin/cp "$BIN_DIR/CodexSkinInjector" "$CONTENTS/MacOS/CodexSkinInjector"
/bin/chmod 755 "$CONTENTS/MacOS/CodexSkinTool"
/bin/chmod 755 "$CONTENTS/MacOS/CodexSkinInjector"

/usr/bin/swift "$ROOT/scripts/generate-icon.swift" "$TEMP_ROOT/AppIcon.png"
for spec in \
    '16 icon_16x16.png' '32 icon_16x16@2x.png' \
    '32 icon_32x32.png' '64 icon_32x32@2x.png' \
    '128 icon_128x128.png' '256 icon_128x128@2x.png' \
    '256 icon_256x256.png' '512 icon_256x256@2x.png' \
    '512 icon_512x512.png' '1024 icon_512x512@2x.png'; do
    set -- $spec
    /usr/bin/sips -z "$1" "$1" "$TEMP_ROOT/AppIcon.png" --out "$ICONSET/$2" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"

/usr/bin/plutil -create xml1 "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDevelopmentRegion string zh_CN' "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string CodexSkinTool' "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string CodexSkinTool' "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string io.github.maoqijie.CodexSkinTool' "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleInfoDictionaryVersion string 6.0' "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string CodexSkinTool' "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${VERSION//./}" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 15.0' "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSHighResolutionCapable bool true' "$CONTENTS/Info.plist"

/usr/bin/codesign --force --deep --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
/bin/mkdir -p "$(/usr/bin/dirname "$OUTPUT")"
/bin/rm -rf "$OUTPUT"
/usr/bin/ditto "$APP" "$OUTPUT"
printf '%s\n' "$OUTPUT"
