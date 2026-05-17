#!/usr/bin/env bash
# Generate Resources/AppIcon.icns from docs/icon.png.
#
# Usage: scripts/make-icon.sh
# Requires: sips and iconutil (both ship with macOS).

set -euo pipefail

cd "$(dirname "$0")/.."

SRC="docs/icon.png"
ICONSET="build/AppIcon.iconset"
OUT="Resources/AppIcon.icns"

if [[ ! -f "$SRC" ]]; then
  echo "Source icon not found: $SRC" >&2
  exit 1
fi

mkdir -p "$ICONSET" "$(dirname "$OUT")"

sips -z 16   16   "$SRC" --out "$ICONSET/icon_16x16.png"        >/dev/null
sips -z 32   32   "$SRC" --out "$ICONSET/icon_16x16@2x.png"     >/dev/null
sips -z 32   32   "$SRC" --out "$ICONSET/icon_32x32.png"        >/dev/null
sips -z 64   64   "$SRC" --out "$ICONSET/icon_32x32@2x.png"     >/dev/null
sips -z 128  128  "$SRC" --out "$ICONSET/icon_128x128.png"      >/dev/null
sips -z 256  256  "$SRC" --out "$ICONSET/icon_128x128@2x.png"   >/dev/null
sips -z 256  256  "$SRC" --out "$ICONSET/icon_256x256.png"      >/dev/null
sips -z 512  512  "$SRC" --out "$ICONSET/icon_256x256@2x.png"   >/dev/null
sips -z 512  512  "$SRC" --out "$ICONSET/icon_512x512.png"      >/dev/null
sips -z 1024 1024 "$SRC" --out "$ICONSET/icon_512x512@2x.png"   >/dev/null

iconutil -c icns -o "$OUT" "$ICONSET"

echo "✓ wrote $OUT"
