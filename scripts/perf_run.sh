#!/bin/bash
# Frame-time check in the iPhone simulator: builds, starts an autopiloted run,
# and prints every hitch (a frame over 25 ms) plus a summary every 5 seconds.
# Usage: scripts/perf_run.sh [seconds] [city|jungle|house|farm]
# NO_BUILD=1 skips the build. CATCART_TIME=120 starts deep in the difficulty ramp.
# The simulator draws with the Mac's graphics chip, so treat its numbers as
# relative: good for spotting hitches and comparing before and after.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UDID="${UDID:-27043DC8-AD54-4138-821B-311D79674E39}"
BUNDLE="com.rexchao.catcart"
APP="$ROOT/DerivedData/Build/Products/Debug-iphonesimulator/CatCart.app"
DURATION="${1:-40}"
WORLD="${2:-city}"
LOG="${LOG:-/tmp/catcart-perf.log}"

if [[ "${NO_BUILD:-}" != "1" ]]; then
  xcodebuild -project "$ROOT/CatCart.xcodeproj" -scheme CatCart \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$ROOT/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build -quiet
fi

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
sleep 0.3

SIMCTL_CHILD_CATCART_PERF=1 SIMCTL_CHILD_CATCART_AUTO_RUN=1 SIMCTL_CHILD_CATCART_GOD=1 \
SIMCTL_CHILD_CATCART_PILOT=1 SIMCTL_CHILD_CATCART_WORLD="$WORLD" \
SIMCTL_CHILD_CATCART_TIME="${CATCART_TIME:-0}" \
  xcrun simctl launch --console "$UDID" "$BUNDLE" >"$LOG" 2>&1 &
RUN=$!
sleep "$DURATION"
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
kill "$RUN" >/dev/null 2>&1 || true
wait "$RUN" 2>/dev/null || true

grep CATCART "$LOG" || echo "no CATCART lines in $LOG"
