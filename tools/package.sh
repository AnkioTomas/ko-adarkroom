#!/bin/bash
# 打包 adarkroom.koplugin：tools/package.sh [版本] [输出 zip]
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-dev}"
OUT="${2:-dist/adarkroom.koplugin-$VERSION.zip}"
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
rm -f "$OUT"
# 在临时副本里把版本号写进 adarkroom/version.lua，源码保持占位符
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R adarkroom.koplugin "$STAGE/adarkroom.koplugin"
sed -i.bak "s/@VERSION@/${VERSION}/g" "$STAGE/adarkroom.koplugin/adarkroom/version.lua"
rm -f "$STAGE/adarkroom.koplugin/adarkroom/version.lua.bak"
(cd "$STAGE" && zip -rq "$OUT" adarkroom.koplugin -x '*.DS_Store')
echo "$OUT"
