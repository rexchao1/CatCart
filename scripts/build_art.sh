#!/bin/bash
# Re-export the saved food and coyote Blender files. Xcode uses the committed
# .scn files directly, so Blender is only needed after changing the source art.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Blender.app if it is installed, else the pip `bpy` module through run_bpy.py
# (what the Linux agents and the CI Mac have). Set BLENDER to pick one yourself.
if [[ -n "${BLENDER:-}" ]]; then
  blender=("$BLENDER" --background)
elif [[ -x /Applications/Blender.app/Contents/MacOS/Blender ]]; then
  blender=(/Applications/Blender.app/Contents/MacOS/Blender --background)
else
  blender=(python3 "$ROOT/scripts/blender/run_bpy.py")
fi
WORK="$(mktemp -d /tmp/catcart-art.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
swiftc -O "$ROOT/scripts/build_game_pickup.swift" -o "$WORK/build_game_pickup"
for kind in coyote food; do
  if [[ "$kind" == coyote ]]; then
    source_file="$ROOT/art/models/coyote/coyote.blend"
    asset_name=coyote_run
  else
    source_file="$ROOT/art/models/food/wet-food.blend"
    asset_name=wet_food
  fi
  if [[ "${blender[0]}" == python3 ]]; then
    "${blender[@]}" "$source_file" "$ROOT/scripts/blender/export_game_pickup.py" -- "$kind" "$WORK/$kind.json"
  else
    "${blender[@]}" "$source_file" --python-exit-code 1 \
      --python "$ROOT/scripts/blender/export_game_pickup.py" -- "$kind" "$WORK/$kind.json"
  fi
  "$WORK/build_game_pickup" "$WORK/$kind.json" "$ROOT/CatCart/Models/$asset_name.scn"
done
