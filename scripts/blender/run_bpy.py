"""Runs a Blender script with the `bpy` Python module when there's no Blender app.

  python3 scripts/blender/run_bpy.py <file.blend or -> <script.py> -- args...

is the same as

  Blender -b <file.blend> --python-exit-code 1 --python <script.py> -- args...

"-" opens no file (the script builds its own scene, like make_kitten_v3.py).
The script sees sys.argv the way Blender hands it over (everything after "--"),
and __file__ as its own path, so scripts that find their neighbors with it work.
Any exception leaves a non-zero exit code, like --python-exit-code 1.
"""
import sys
from pathlib import Path

import bpy

if len(sys.argv) < 3:
    sys.exit(__doc__)
blend, script = sys.argv[1], Path(sys.argv[2]).resolve()
rest = sys.argv[3:]
if blend != "-":
    bpy.ops.wm.open_mainfile(filepath=str(Path(blend).resolve()))
sys.argv = ["blender", "--background", "--python", str(script)] + (rest if rest and rest[0] == "--" else ["--"] + rest if rest else [])
code = compile(script.read_text(), str(script), "exec")
exec(code, {"__name__": "__main__", "__file__": str(script)})
