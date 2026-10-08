#!/bin/bash
# Re-export the kitten: art/models/kitten/cat.blend -> CatCart/Models/cat_kitten.scn.
# Xcode uses the committed .scn, so Blender is only needed after changing her.
#
# To change her shape, edit scripts/blender/make_kitten_v3.py and rebuild the
# study first (it saves the .blend and renders it), then copy it over cat.blend:
#   Blender -b --python-exit-code 1 --python scripts/blender/make_kitten_v3.py -- art/options/kitten-cute-v3
#   cp art/options/kitten-cute-v3/kitten-cute-v3.blend art/models/kitten/cat.blend
# Then run this, then swift scripts/preview_kitten.swift [dir] to look at her.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
WORK="$(mktemp -d /tmp/catcart-kitten.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
"$BLENDER" --background "$ROOT/art/models/kitten/cat.blend" --python-exit-code 1 \
  --python "$ROOT/scripts/blender/export_kitten.py" -- "$WORK"
swiftc -O "$ROOT/scripts/build_kitten.swift" -o "$WORK/build_kitten"
"$WORK/build_kitten" "$WORK/kitten.json" "$ROOT/CatCart/Models/cat_kitten.scn"
