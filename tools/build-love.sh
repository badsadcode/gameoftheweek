#!/usr/bin/env bash
# Builds one LÖVE game: a fused Windows exe zip, the .love file, and (with WEB=1) a love.js web build.
#   usage:  LOVE_WIN=<extracted love-11.5-win64 folder> tools/build-love.sh games/01-frostline dist/01-frostline
# Reads exe_name, title and web from the game's game.json. Game source lives in <game>/src.
set -euo pipefail

GAME="$(cd "${1:?game folder}" && pwd)"
mkdir -p "${2:?output folder}"
OUT="$(cd "$2" && pwd)"
LOVE_WIN="$(cd "${LOVE_WIN:?set LOVE_WIN to the extracted love-win64 folder}" && pwd)"

NAME="$(jq -r '.exe_name' "$GAME/game.json")"
TITLE="$(jq -r '.title' "$GAME/game.json")"
WANT_WEB="$(jq -r '.web // false' "$GAME/game.json")"

rm -rf "$OUT/$NAME" "$OUT/$NAME-win64.zip" "$OUT/game.love" "$OUT/play"

# 1) .love = zipped source (dev-only files left out)
(cd "$GAME/src" && zip -9 -q -r "$OUT/game.love" . -x devtools.lua)

# 2) fused exe + LÖVE's DLLs, zipped
mkdir -p "$OUT/$NAME"
cat "$LOVE_WIN/love.exe" "$OUT/game.love" > "$OUT/$NAME/$NAME.exe"
cp "$LOVE_WIN"/*.dll "$LOVE_WIN/license.txt" "$OUT/$NAME/"
[ -f "$GAME/README.md" ] && cp "$GAME/README.md" "$OUT/$NAME/README.txt"
(cd "$OUT" && zip -9 -q -r "$NAME-win64.zip" "$NAME")
echo "[$NAME] windows: $OUT/$NAME-win64.zip"

# 3) optional web build (never fails the whole build)
if [ "${WEB:-0}" = "1" ] && [ "$WANT_WEB" = "true" ]; then
  if npx --yes love.js@11.4.1 -c -t "$TITLE" "$OUT/game.love" "$OUT/play"; then
    echo "[$NAME] web: $OUT/play"
  else
    echo "[$NAME] web build failed, skipping" >&2
    rm -rf "$OUT/play"
  fi
fi
