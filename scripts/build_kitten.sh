#!/bin/bash
# Re-export the kitten: art/models/kitten/cat.blend -> CatCart/Models/cat_kitten.scn.
# Xcode uses the committed .scn, so Blender is only needed after changing her.
#
# To change her shape, edit scripts/blender/make_kitten_v4.py and rebuild the
# study first (it saves the .blend and renders it), then copy it over cat.blend:
#   Blender -b --python-exit-code 1 --python scripts/blender/make_kitten_v4.py -- art/options/kitten-cute-v4
#   cp art/options/kitten-cute-v4/kitten-cute-v4.blend art/models/kitten/cat.blend
# Then run this, then swift scripts/preview_kitten.swift [dir] to look at her.
#
# The other cats the player can pick: scripts/build_kitten.sh BREED builds
# art/models/cats/BREED.blend into CatCart/Models/cat_BREED.scn. Make the
# .blend the same way, with --breed:
#   Blender -b --python-exit-code 1 --python scripts/blender/make_kitten_v4.py -- art/options/cats/bean --breed bean
#   cp art/options/cats/bean/cat-bean.blend art/models/cats/bean.blend
#
# Blender: $BLENDER if set, else Blender.app, else the `bpy` Python module
# through scripts/blender/run_bpy.py (a machine with `pip install bpy` and no
# Blender app, like a Linux box). The Swift step needs a Mac either way.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BREED="${1:-}"
SRC="$ROOT/art/models/kitten/cat.blend"
DEST="$ROOT/CatCart/Models/cat_kitten.scn"
if [ -n "$BREED" ]; then
  SRC="$ROOT/art/models/cats/$BREED.blend"
  DEST="$ROOT/CatCart/Models/cat_$BREED.scn"
fi
WORK="$(mktemp -d /tmp/catcart-kitten.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
BLENDER_APP="/Applications/Blender.app/Contents/MacOS/Blender"
if [ -n "${BLENDER:-}" ]; then
  "$BLENDER" --background "$SRC" --python-exit-code 1 \
    --python "$ROOT/scripts/blender/export_kitten.py" -- "$WORK"
elif [ -x "$BLENDER_APP" ]; then
  "$BLENDER_APP" --background "$SRC" --python-exit-code 1 \
    --python "$ROOT/scripts/blender/export_kitten.py" -- "$WORK"
else
  python3 "$ROOT/scripts/blender/run_bpy.py" "$SRC" \
    "$ROOT/scripts/blender/export_kitten.py" -- "$WORK"
fi
swiftc -O "$ROOT/scripts/build_kitten.swift" -o "$WORK/build_kitten"
"$WORK/build_kitten" "$WORK/kitten.json" "$DEST"
