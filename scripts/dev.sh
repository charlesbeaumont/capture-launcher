#!/usr/bin/env bash
# Watch Sources/ and project.yml; on save, rebuild Debug and relaunch Capture.
#
# Usage: scripts/dev.sh
# Requires: brew install fswatch xcodegen

set -uo pipefail

command -v fswatch  >/dev/null || { echo "fswatch not found. brew install fswatch" >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "xcodegen not found. brew install xcodegen" >&2; exit 1; }

cd "$(dirname "$0")/.."

APP="build/Build/Products/Debug/Capture.app"
LOG="/tmp/capture-dev-build.log"
RUNTIME_LOG="/tmp/capture-runtime.log"

rebuild() {
  printf '[%s] building...\n' "$(date +%H:%M:%S)"
  xcodegen generate >/dev/null
  if xcodebuild \
      -project Capture.xcodeproj \
      -scheme Capture \
      -configuration Debug \
      -derivedDataPath build \
      build >"$LOG" 2>&1; then
    pkill -f "$APP/Contents/MacOS/Capture" 2>/dev/null || true
    sleep 0.2
    nohup "$APP/Contents/MacOS/Capture" >>"$RUNTIME_LOG" 2>&1 &
    disown
    printf '[%s] relaunched (runtime log: %s)\n' "$(date +%H:%M:%S)" "$RUNTIME_LOG"
  else
    printf '[%s] build failed:\n' "$(date +%H:%M:%S)"
    grep -E "error:|warning:" "$LOG" | head -20
  fi
}

rebuild

echo "watching Sources/ and project.yml..."
fswatch -o -l 0.5 Sources project.yml | while read -r _; do
  rebuild
done
