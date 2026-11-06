#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP="$ROOT/ScreenStay.app"
BUILD="$ROOT/.build"
CACHE="$BUILD/module-cache"
MIN_MACOS="13.0"

# This machine only has Command Line Tools. The 15.4 SDK matches the installed
# Swift compiler; set SCREENSTAY_SDK to override it on another machine.
SDK="${SCREENSTAY_SDK:-}"
if [[ -z "$SDK" ]]; then
    if [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
        SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
    else
        SDK="$(xcrun --show-sdk-path)"
    fi
fi

if [[ ! -d "$SDK" ]]; then
    echo "找不到 macOS SDK: $SDK" >&2
    exit 1
fi
if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
    echo "找不到 Resources/AppIcon.icns" >&2
    exit 1
fi

STAGING="$(mktemp -d /tmp/ScreenStay-build.XXXXXX)"
STAGED_APP="$STAGING/ScreenStay.app"
cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT

echo "==> SDK: $SDK"
echo "==> 清理构建目录"
rm -rf "$APP" "$BUILD"
mkdir -p "$BUILD" "$CACHE" "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"

COMMON_FLAGS=(
    -swift-version 5
    -sdk "$SDK"
    -module-cache-path "$CACHE"
    -import-objc-header "$ROOT/Sources/NowPlayingBridge.h"
    -O
    -framework AppKit
    -framework Foundation
    -framework CoreAudio
    -framework IOKit
    -framework ServiceManagement
)

echo "==> 编译 Objective-C Now Playing bridge (arm64)"
clang -fobjc-arc -c Sources/NowPlayingBridge.m \
    -o "$BUILD/NowPlayingBridge-arm64.o" \
    -isysroot "$SDK" \
    -target "arm64-apple-macos${MIN_MACOS}" \
    -I Sources

echo "==> 编译 Perl probe dylib (arm64)"
clang -dynamiclib -fobjc-arc -framework Foundation \
    -isysroot "$SDK" \
    -target "arm64-apple-macos${MIN_MACOS}" \
    Sources/PerlNowPlayingProbe.m \
    -o "$BUILD/libScreenStayNowPlaying-arm64.dylib"

echo "==> 编译 arm64"
swiftc "${COMMON_FLAGS[@]}" \
    -target "arm64-apple-macos${MIN_MACOS}" \
    Sources/*.swift "$BUILD/NowPlayingBridge-arm64.o" \
    -o "$BUILD/ScreenStay-arm64"

echo "==> 编译 Objective-C Now Playing bridge (x86_64)"
clang -fobjc-arc -c Sources/NowPlayingBridge.m \
    -o "$BUILD/NowPlayingBridge-x86_64.o" \
    -isysroot "$SDK" \
    -target "x86_64-apple-macos${MIN_MACOS}" \
    -I Sources

echo "==> 编译 Perl probe dylib (x86_64)"
clang -dynamiclib -fobjc-arc -framework Foundation \
    -isysroot "$SDK" \
    -target "x86_64-apple-macos${MIN_MACOS}" \
    Sources/PerlNowPlayingProbe.m \
    -o "$BUILD/libScreenStayNowPlaying-x86_64.dylib"

echo "==> 编译 x86_64"
swiftc "${COMMON_FLAGS[@]}" \
    -target "x86_64-apple-macos${MIN_MACOS}" \
    Sources/*.swift "$BUILD/NowPlayingBridge-x86_64.o" \
    -o "$BUILD/ScreenStay-x86_64"

echo "==> 合并为通用二进制"
lipo -create \
    "$BUILD/ScreenStay-arm64" \
    "$BUILD/ScreenStay-x86_64" \
    -output "$STAGED_APP/Contents/MacOS/ScreenStay"
chmod +x "$STAGED_APP/Contents/MacOS/ScreenStay"

lipo -create \
    "$BUILD/libScreenStayNowPlaying-arm64.dylib" \
    "$BUILD/libScreenStayNowPlaying-x86_64.dylib" \
    -output "$STAGED_APP/Contents/Resources/libScreenStayNowPlaying.dylib"

cp "$ROOT/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Sources/nowplaying-probe.pl" "$STAGED_APP/Contents/Resources/nowplaying-probe.pl"

# This workspace is backed by a file provider that re-adds FinderInfo xattrs
# after xattr -cr. Signing inside /tmp avoids "resource fork, Finder
# information, or similar detritus not allowed".
xattr -cr "$STAGED_APP" 2>/dev/null || true

echo "==> 签名内置 dylib"
codesign --force --sign - "$STAGED_APP/Contents/Resources/libScreenStayNowPlaying.dylib"

echo "==> ad-hoc 签名"
codesign --force --deep --sign - \
    --identifier com.zzerfu.ScreenStay \
    "$STAGED_APP"

echo "==> 校验"
plutil -lint "$STAGED_APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

echo "==> 复制到工作区"
ditto --norsrc "$STAGED_APP" "$APP"
xattr -cr "$APP" 2>/dev/null || true
if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
    echo "工作区副本签名校验通过"
else
    echo "提示：工作区文件提供商重新附加了 FinderInfo，已构建的 /tmp 副本签名有效；打包脚本会重新签名。"
fi
lipo -info "$APP/Contents/MacOS/ScreenStay"

echo
echo "构建完成: $APP"
echo "运行: open \"$APP\""
