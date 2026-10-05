#!/bin/bash
# Camera framing check in the iPhone simulator: six frozen frames from the
# short-then-tall cat tree mix (CATCART_WAVE=50), the moments where the cat can
# hide the road ahead: a plain run, the top of a jump, jumping up to a tall roof,
# just landed on it, riding it, and the top of a jump off it. Saves each frame
# and a side-by-side sheet.png.
# Usage: scripts/camera_shots.sh [out dir] [world]
# NO_BUILD=1 skips the build. CAM="4,4.4,12,0.6,50" tries a framing (height,
# distance back, aim, jump follow, field of view) without changing code.
# Each moment is a separate launch with a CATCART_SWIPES "freeze", taken 1.5 s
# into the freeze: the app takes a varying half second or so to start, and a
# shot right at the freeze time can land before it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UDID="${UDID:-27043DC8-AD54-4138-821B-311D79674E39}"
BUNDLE="com.rexchao.catcart"
APP="$ROOT/DerivedData/Build/Products/Debug-iphonesimulator/CatCart.app"
OUT="${1:-/tmp/catcart-shots/camera}"
WORLD="${2:-city}"
mkdir -p "$OUT"

if [[ "${NO_BUILD:-}" != "1" ]]; then
  xcodebuild -project "$ROOT/CatCart.xcodeproj" -scheme CatCart \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$ROOT/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build -quiet
fi
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"

# shot NAME PILOT SWIPES SHOT_AT RUN_FOR
shot() {
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 0.3
  SIMCTL_CHILD_CATCART_AUTO_RUN=1 SIMCTL_CHILD_CATCART_GOD=1 SIMCTL_CHILD_CATCART_WAVE=50 \
  SIMCTL_CHILD_CATCART_PILOT="$2" SIMCTL_CHILD_CATCART_SWIPES="$3" \
  SIMCTL_CHILD_CATCART_WORLD="$WORLD" SIMCTL_CHILD_CATCART_CAM="${CAM:-}" \
    xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  sleep "$4"
  xcrun simctl io "$UDID" screenshot "$OUT/$1.png" >/dev/null 2>&1
  sleep "$5"
}

shot 1_road           1 "1.6:freeze"         3.1 1
shot 2_road_jump      0 "1.1:up,1.5:freeze"  3.0 1
shot 3_jump_up_tall   1 "2.95:freeze"        4.5 1
shot 4_landed_tall    1 "3.2:freeze"         4.7 1
shot 5_riding_tall    1 "3.65:freeze"        5.1 1
shot 6_jump_off_tall  1 "3.3:up,3.7:freeze"  5.2 1
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true

python3 - "$OUT" <<'EOF'
import sys, glob, os
from PIL import Image, ImageDraw
d = sys.argv[1]
files = sorted(glob.glob(d + "/[0-9]_*.png"))
ims = [Image.open(f).convert("RGB") for f in files]
w = 300
h = int(ims[0].height * w / ims[0].width)
sheet = Image.new("RGB", (w * len(ims), h + 24), "white")
draw = ImageDraw.Draw(sheet)
for i, (f, im) in enumerate(zip(files, ims)):
    sheet.paste(im.resize((w, h)), (i * w, 24))
    draw.text((i * w + 6, 6), os.path.basename(f)[:-4], fill="black")
sheet.save(d + "/sheet.png")
EOF
echo "$OUT/sheet.png"
