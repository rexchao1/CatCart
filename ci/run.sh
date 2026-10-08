#!/bin/bash
# CI driver for .github/workflows/sim-shots.yml. Writes everything to out/.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/out"
mkdir -p "$OUT/shots" "$OUT/preview" "$OUT/logs"
exec > >(tee -a "$ROOT/ci-run.log") 2>&1

BUNDLE="com.rexchao.catcart"
step() { echo; echo "=== $* ($(date +%H:%M:%S))"; }

# 0. Boot a simulator now, in the background: a fresh one takes minutes.
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
best = None
for rt, devs in d.items():
    if "iOS" not in rt: continue
    for x in devs:
        if x["name"] in ("iPhone 17", "iPhone 17 Pro", "iPhone 16 Pro", "iPhone 16"):
            v = rt.split("iOS-")[-1].replace("-", ".")
            key = (tuple(int(p) for p in v.split(".")), x["name"] == "iPhone 17")
            if best is None or key > best[0]: best = (key, x["udid"], x["name"], rt)
print(best[1] if best else "")
print(best, file=sys.stderr)
')
echo "UDID=$UDID"
[[ -n "$UDID" ]] || { xcrun simctl list devices available; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null &

# 1. Kitten: if a fresh Blender export is here, turn it into the game model.
if [[ -f ci/kitten/kitten.json ]]; then
  step "build kitten"
  mkdir -p "$OUT/models"
  { swiftc -O -o /tmp/build_kitten scripts/build_kitten.swift && \
    /tmp/build_kitten ci/kitten/kitten.json CatCart/Models/cat_kitten.scn && \
    cp CatCart/Models/cat_kitten.scn "$OUT/models/"; } || { echo "KITTEN BUILD FAILED"; exit 1; }
fi

# 2. Offscreen previews of the kitten model (no simulator needed).
step "preview kitten"
swiftc -O -o /tmp/preview_kitten scripts/preview_kitten.swift && /tmp/preview_kitten "$OUT/preview" || echo "PREVIEW FAILED"

# 3. Build the app for the simulator.
step "xcodebuild"
xcodebuild -project CatCart.xcodeproj -scheme CatCart \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build -quiet > "$OUT/logs/build.log" 2>&1
BUILD=$?
grep -E "error:|warning: .*GameScene|warning: .*KittenCart|warning: .*Hud" "$OUT/logs/build.log" | head -80
if [[ $BUILD -ne 0 ]]; then
  echo "BUILD FAILED"
  tail -60 "$OUT/logs/build.log"
  exit 1
fi
echo "BUILD OK"
APP="$ROOT/DerivedData/Build/Products/Debug-iphonesimulator/CatCart.app"

step "boot"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

# launch NAME [ENV=VALUE ...]: start the game with those CATCART settings,
# console output into logs/NAME.log.
launch() {
  local name="$1"; shift
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 0.5
  local envs=()
  for kv in "$@"; do envs+=("SIMCTL_CHILD_$kv"); done
  env ${envs[@]+"${envs[@]}"} xcrun simctl launch --terminate-running-process \
    --stdout="$OUT/logs/$name.log" --stderr="$OUT/logs/$name.err" "$UDID" "$BUNDLE" >/dev/null
}
shot() { xcrun simctl io "$UDID" screenshot "$OUT/shots/$1.png" >/dev/null 2>&1 || echo "shot $1 failed"; }

# 4. The shots for this round live in ci/shots.sh.
step "shots"
source ci/shots.sh

xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true

# Big PNGs become JPEGs, except the ones named *hero*.
for f in "$OUT"/shots/*.png "$OUT"/preview/*.png; do
  [[ -f "$f" ]] || continue
  case "$f" in *hero*) continue ;; esac
  sips -s format jpeg -s formatOptions 82 "$f" --out "${f%.png}.jpg" >/dev/null && rm "$f"
done
step "done"
ls -la "$OUT"/*
