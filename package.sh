#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

VERSION="1.2.3"
APP="$ROOT/ScreenStay.app"
DIST="$ROOT/dist"

if [[ ! -d "$APP" ]]; then
    echo "找不到 $APP，请先运行 build.sh。" >&2
    exit 1
fi

WORK="$(mktemp -d /tmp/ScreenStay-package.XXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# The workspace is backed by a file provider that re-adds FinderInfo xattrs to
# app bundles. Re-sign a clean copy inside /tmp before packaging so the
# delivered app always passes `codesign --verify`.
STAGED_APP="$WORK/ScreenStay.app"
ditto --norsrc "$APP" "$STAGED_APP"
xattr -cr "$STAGED_APP" 2>/dev/null || true
codesign --force --deep --sign - \
    --identifier com.zzerfu.ScreenStay \
    "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

rm -rf "$DIST"
mkdir -p "$DIST"

# Zip: app + installer + docs. This is the primary deliverable.
ZIP_STAGE="$WORK/zip/ScreenStay"
mkdir -p "$ZIP_STAGE"
ditto --norsrc "$STAGED_APP" "$ZIP_STAGE/ScreenStay.app"
cp "$ROOT/README.md" "$ZIP_STAGE/README.md"
cp "$ROOT/CHANGELOG.md" "$ZIP_STAGE/CHANGELOG.md"
cp "$ROOT/install.command" "$ZIP_STAGE/install.command"
chmod 755 "$ZIP_STAGE/install.command"

ditto -c -k --keepParent --norsrc "$ZIP_STAGE" "$DIST/ScreenStay-$VERSION.zip"
unzip -t "$DIST/ScreenStay-$VERSION.zip" >/dev/null

# DMG with a Finder layout (Quiet Meadow background, drag-to-Applications).
# Uses Homebrew create-dmg if present, otherwise the vendored MIT copy in
# scripts/create-dmg. Needs a GUI session (Finder AppleScript). Never fail
# packaging because of the DMG; ZIP is the primary deliverable.
DMG_STAGE="$WORK/dmg"
mkdir -p "$DMG_STAGE"
ditto --norsrc "$STAGED_APP" "$DMG_STAGE/ScreenStay.app"

BG="$ROOT/Resources/dmg-background.png"
if command -v tiffutil >/dev/null 2>&1 && [[ -f "$ROOT/Resources/dmg-background@2x.png" ]]; then
    tiffutil -cathidpicheck "$BG" "$ROOT/Resources/dmg-background@2x.png" \
        -out "$WORK/dmg-background.tiff" >/dev/null 2>&1 && BG="$WORK/dmg-background.tiff"
fi

CREATE_DMG="$(command -v create-dmg || echo "$ROOT/scripts/create-dmg/create-dmg")"
DMG_OUT="$DIST/ScreenStay-$VERSION.dmg"
if "$CREATE_DMG" \
    --volname "ScreenStay" \
    --volicon "$ROOT/Resources/AppIcon.icns" \
    --background "$BG" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --text-size 12 \
    --icon "ScreenStay.app" 180 200 \
    --hide-extension "ScreenStay.app" \
    --app-drop-link 480 200 \
    --format UDZO \
    --filesystem HFS+ \
    --overwrite \
    "$DMG_OUT" \
    "$DMG_STAGE"; then
    hdiutil verify "$DMG_OUT" >/dev/null
else
    rm -f "$DMG_OUT"
    echo "提示：当前环境无法创建 DMG，已跳过；ZIP 安装包可正常使用。"
fi

echo "打包完成:"
ls -lh "$DIST"
