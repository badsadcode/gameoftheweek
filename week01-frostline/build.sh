#!/usr/bin/env bash
# Builds Frostline for Windows (fused LÖVE exe) and packages it as a zip.
#   usage: ./build.sh <path-to-love-win64-folder> [out-dir]
# The LÖVE folder is the extracted love-11.5-win64.zip from https://github.com/love2d/love/releases
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LOVE_WIN="${1:?path to extracted love-11.5-win64 folder}"
OUT="${2:-$HERE/dist}"
NAME="Frostline"

mkdir -p "$OUT"
# absolute paths, since we cd around below
LOVE_WIN="$(cd "$LOVE_WIN" && pwd)"
OUT="$(cd "$OUT" && pwd)"
rm -rf "$OUT/$NAME" "$OUT/$NAME-win64.zip" "$OUT/frostline.love"

# 1) the .love file (game source zipped, devtools left out)
(cd "$HERE/game" && zip -9 -q -r "$OUT/frostline.love" . -x devtools.lua)

# 2) fuse: love.exe + .love = game exe; ship it next to LÖVE's DLLs
mkdir -p "$OUT/$NAME"
cat "$LOVE_WIN/love.exe" "$OUT/frostline.love" > "$OUT/$NAME/$NAME.exe"
cp "$LOVE_WIN"/*.dll "$LOVE_WIN/license.txt" "$OUT/$NAME/"
cp "$HERE/README.md" "$OUT/$NAME/README.txt"

(cd "$OUT" && zip -9 -q -r "$NAME-win64.zip" "$NAME")
echo "Built $OUT/$NAME-win64.zip"
