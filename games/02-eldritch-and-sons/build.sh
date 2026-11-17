#!/usr/bin/env bash
# Builds Eldritch & Sons (Godot 4) for Windows and the web.
#   usage: build.sh <out-dir>        (run from this folder; tools/build-all.sh does that)
# Downloads Godot + its export templates once into $GODOT_CACHE (default ~/.cache/godot);
# CI caches that folder between runs. Only the two templates we need are kept (~100 MB, not 1.2 GB).
set -euo pipefail

VERSION="4.4.1"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "${1:?out dir}"
OUT="$(cd "$1" && pwd)"
CACHE="${GODOT_CACHE:-$HOME/.cache/godot}"
NAME="EldritchAndSons"
GODOT="$CACHE/Godot_v${VERSION}-stable_linux.x86_64"
TPL_DIR="$HOME/.local/share/godot/export_templates/${VERSION}.stable"
mkdir -p "$CACHE/templates" "$TPL_DIR"

if [ ! -x "$GODOT" ]; then
  echo "[eldritch] downloading Godot $VERSION"
  curl -sSL -o "$CACHE/godot.zip" "https://github.com/godotengine/godot/releases/download/${VERSION}-stable/Godot_v${VERSION}-stable_linux.x86_64.zip"
  unzip -q -o "$CACHE/godot.zip" -d "$CACHE" && rm "$CACHE/godot.zip"
  chmod +x "$GODOT"
fi

NEED=(windows_release_x86_64.exe web_nothreads_release.zip version.txt)
missing=0
for f in "${NEED[@]}"; do [ -f "$CACHE/templates/$f" ] || missing=1; done
if [ "$missing" = 1 ]; then
  echo "[eldritch] downloading export templates (once)"
  curl -sSL -o "$CACHE/templates.tpz" "https://github.com/godotengine/godot/releases/download/${VERSION}-stable/Godot_v${VERSION}-stable_export_templates.tpz"
  for f in "${NEED[@]}"; do unzip -q -o -j "$CACHE/templates.tpz" "templates/$f" -d "$CACHE/templates"; done
  rm -f "$CACHE/templates.tpz"
fi
cp -f "$CACHE/templates/"* "$TPL_DIR/"

cd "$HERE/src"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

rm -rf "$OUT/$NAME" "$OUT/$NAME-win64.zip" "$OUT/play"
mkdir -p "$OUT/$NAME" "$OUT/play"
"$GODOT" --headless --path . --export-release "Windows Desktop" "$OUT/$NAME/$NAME.exe"
cp "$HERE/README.md" "$OUT/$NAME/README.txt"
(cd "$OUT" && zip -9 -q -r "$NAME-win64.zip" "$NAME")
echo "[eldritch] windows: $OUT/$NAME-win64.zip"

if "$GODOT" --headless --path . --export-release "Web" "$OUT/play/index.html" && [ -f "$OUT/play/index.html" ]; then
  echo "[eldritch] web: $OUT/play"
else
  echo "[eldritch] web export failed, skipping" >&2
  rm -rf "$OUT/play"
fi
