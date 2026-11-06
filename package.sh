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

# DMG is a nice extra, but disk-image creation is not available in every
# sandboxed build environment. Never fail packaging because of it.
DMG_STAGE="$WORK/dmg"
mkdir -p "$DMG_STAGE"
ditto --norsrc "$STAGED_APP" "$DMG_STAGE/ScreenStay.app"
ln -s /Applications "$DMG_STAGE/Applications"
cp "$ROOT/README.md" "$DMG_STAGE/使用说明.md"
cp "$ROOT/CHANGELOG.md" "$DMG_STAGE/更新记录.md"

if hdiutil create \
    -volname "ScreenStay $VERSION" \
    -srcfolder "$DMG_STAGE" \
    -ov \
    -format UDZO \
    "$DIST/ScreenStay-$VERSION.dmg" >/dev/null 2>&1; then
    hdiutil verify "$DIST/ScreenStay-$VERSION.dmg" >/dev/null
else
    rm -f "$DIST/ScreenStay-$VERSION.dmg"
    echo "提示：当前环境无法创建 DMG，已跳过；ZIP 安装包可正常使用。"
fi

echo "打包完成:"
ls -lh "$DIST"
