# Runs a Blender script without the Blender app, through the `bpy` Python
# module (pip install bpy; it needs the Python version bpy was built for).
# Works on Linux and on a CI Mac, where there is no Blender.app.
#
#   python3 scripts/blender/run_bpy.py <file.blend or -> <script.py> [-- args...]
#
# It is the same as:
#   Blender --background <file.blend> --python <script.py> -- args...
import runpy
import sys

import bpy

blend, script, *rest = sys.argv[1:]
if rest and rest[0] == "--":
    rest = rest[1:]
if blend != "-":
    bpy.ops.wm.open_mainfile(filepath=blend)
sys.argv = ["blender", "--background", "--python", script, "--", *rest]
runpy.run_path(script, run_name="__main__")
