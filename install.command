#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$ROOT/ScreenStay.app"
DEST_APP="/Applications/ScreenStay.app"

if [[ ! -d "$SOURCE_APP" ]]; then
    echo "找不到 $SOURCE_APP，请先运行 build.sh 构建。"
    read -r -p "按回车键退出…" _
    exit 1
fi

if [[ "$DEST_APP" != "/Applications/ScreenStay.app" ]]; then
    echo "安装路径异常，已中止。"
    exit 1
fi

killall ScreenStay 2>/dev/null || true
sleep 0.5

echo "正在安装到 $DEST_APP …"
rm -rf "$DEST_APP"
ditto --norsrc "$SOURCE_APP" "$DEST_APP"
xattr -cr "$DEST_APP" 2>/dev/null || true
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

# Re-sign after copying: the workspace copy can acquire FinderInfo xattrs from
# the file provider, and /Applications must contain a clean, valid signature.
codesign --force --deep --sign - \
    --identifier com.zzerfu.ScreenStay \
    "$DEST_APP"
codesign --verify --deep --strict "$DEST_APP"

open "$DEST_APP"
echo
echo "已安装并启动 ScreenStay。"
echo "菜单栏右上角会出现一个显示器图标，点击即可开关。"
echo
echo "提示：如果之前已经开过“开机自启”，移动 App 后请关闭再打开一次该开关。"
read -r -p "按回车键关闭此窗口…" _
