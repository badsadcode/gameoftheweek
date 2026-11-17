#!/usr/bin/env bash
# Assembles the GitHub Pages site from site/ + every games/*/ folder + build outputs in dist/.
#   usage: tools/assemble-site.sh <dist-dir> <site-out-dir>
# Result:
#   index.html, game.html, style.css, app.js, config.json   (from site/)
#   games.json                                              (all game.json files, newest week first)
#   games/<slug>/{game.json, devlog.json, screenshot.png, <Name>-win64.zip, game.love, play/}
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${1:?dist dir}"
OUT="${2:?site output dir}"

rm -rf "$OUT"
mkdir -p "$OUT/games"
cp -r "$ROOT/site/." "$OUT/"

for dir in "$ROOT"/games/*/; do
  slug="$(basename "$dir")"
  [ -f "$dir/game.json" ] || continue
  dest="$OUT/games/$slug"
  mkdir -p "$dest"
  for f in game.json devlog.json "$dir"/*.png; do
    f="$(basename "$f")"
    [ -f "$dir/$f" ] && cp "$dir/$f" "$dest/"
  done
  [ -f "$dest/devlog.json" ] || echo "[]" > "$dest/devlog.json"
  name="$(jq -r '.exe_name // empty' "$dir/game.json")"
  if [ -d "$DIST/$slug" ]; then
    [ -n "$name" ] && [ -f "$DIST/$slug/$name-win64.zip" ] && cp "$DIST/$slug/$name-win64.zip" "$dest/"
    [ -f "$DIST/$slug/game.love" ] && cp "$DIST/$slug/game.love" "$dest/"
    [ -d "$DIST/$slug/play" ] && cp -r "$DIST/$slug/play" "$dest/play"
  fi
  # tell the site what actually got built
  jq --arg zip "$( [ -n "${name:-}" ] && [ -f "$dest/${name:-x}-win64.zip" ] && echo "games/$slug/$name-win64.zip" )" \
     --argjson play "$( [ -d "$dest/play" ] && echo true || echo false )" \
     '. + {download: $zip, has_web: $play}' "$dir/game.json" > "$dest/game.json"
done

jq -s 'sort_by(-.week)' "$OUT"/games/*/game.json > "$OUT/games.json"
touch "$OUT/.nojekyll"
echo "site assembled in $OUT ($(jq length "$OUT/games.json") games)"
