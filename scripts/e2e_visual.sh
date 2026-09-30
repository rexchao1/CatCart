#!/bin/bash
# Drive the iPhone simulator: build, auto-run, screenshot a full loop.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UDID="${UDID:-27043DC8-AD54-4138-821B-311D79674E39}"
BUNDLE="com.rexchao.catcart"
APP="$ROOT/DerivedData/Build/Products/Debug-iphonesimulator/CatCart.app"
OUT="${OUT:-/tmp/catcart-shots/e2e}"
mkdir -p "$OUT"

echo "building..."
xcodebuild -project "$ROOT/CatCart.xcodeproj" -scheme CatCart \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$ROOT/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "install..."
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true

launch() {
  local world="${1:-}"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 0.3
  if [[ -n "$world" ]]; then
    SIMCTL_CHILD_CATCART_AUTO_RUN=1 SIMCTL_CHILD_CATCART_GOD=1 SIMCTL_CHILD_CATCART_WORLD="$world" \
      xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  else
    SIMCTL_CHILD_CATCART_AUTO_RUN=1 SIMCTL_CHILD_CATCART_GOD=1 \
      xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  fi
}

shot() {
  xcrun simctl io "$UDID" screenshot "$OUT/$1.png" >/dev/null
}

echo "city run + motion burst..."
launch
sleep 0.5
shot "city_t0"
for i in 1 2 3 4 5 6 7 8; do
  sleep 0.4
  shot "city_burst_$i"
done
sleep 1.2
shot "run_t5s"
sleep 3
shot "run_t8s"
sleep 2.2
shot "run_t10s"
sleep 1.6
shot "run_t12s"
sleep 6
shot "run_t18s"
sleep 4
shot "run_t22s"
sleep 10
shot "run_t32s"

echo "per-world stills..."
for w in jungle house farm; do
  launch "$w"
  sleep 1.8
  shot "$w"
done

echo "done -> $OUT"
ls -1 "$OUT"
