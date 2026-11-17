#!/usr/bin/env bash
# Builds every games/*/ folder into dist/<slug>/. Any engine, any genre. Each week picks ONE of:
#
#   1) "engine": "love" in game.json        -> tools/build-love.sh does everything (needs $LOVE_WIN)
#   2) a build.sh in the game folder         -> run as: build.sh <out-dir>   (Godot, Python, C, web, ...)
#      it may download whatever tools it needs (runs on ubuntu-latest in CI)
#   3) a prebuilt/ folder in the game folder -> copied as-is (for engines that can't build in CI, e.g. Unity)
#
# Whatever builds it, the output folder should contain:
#   <exe_name>-win64.zip   the Windows download (exe_name from game.json)
#   play/index.html        optional browser version
#
#   usage: tools/build-all.sh [dist-dir]
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${1:-$ROOT/dist}"
mkdir -p "$DIST"
DIST="$(cd "$DIST" && pwd)"
failed=0

for dir in "$ROOT"/games/*/; do
  dir="${dir%/}"
  slug="$(basename "$dir")"
  [ -f "$dir/game.json" ] || continue
  engine="$(jq -r '.engine // empty' "$dir/game.json")"
  out="$DIST/$slug"
  mkdir -p "$out"
  echo "::group::$slug (${engine:-unknown engine})"
  if [ -f "$dir/build.sh" ]; then
    (cd "$dir" && bash ./build.sh "$out") || { echo "::warning::$slug build.sh failed"; failed=1; }
  elif [ "$engine" = "love" ]; then
    bash "$ROOT/tools/build-love.sh" "$dir" "$out" || { echo "::warning::$slug LÖVE build failed"; failed=1; }
  elif [ -d "$dir/prebuilt" ]; then
    cp -r "$dir/prebuilt/." "$out/"
  else
    echo "::warning::$slug has no build.sh, prebuilt/ folder or known engine - nothing to download"
  fi
  echo "::endgroup::"
done

# one broken week must not take the whole site down: warn, don't fail
[ "$failed" = 0 ] || echo "::warning::some games failed to build; the site still deploys"
exit 0
