# Coyote Blender model

Goal: make a coyote that belongs beside the natural-proportion kitten and turquoise wet-food can.

Constraints: lean canine anatomy, pointed ears, narrow muzzle, ragged fur, amber eyes, bared teeth. Warm tan and dark brown keep danger distinct from the turquoise pickup. Save `art/models/coyote/coyote.blend`; keep previews under `art/options/coyote/`. Do not replace the live galloping model during this art pass.

Done when: the editable model, materials, and snarl preview are saved; front, side, and portrait renders are checked; the Blender file opens.

- [x] Read the current art direction and existing coyote builder.
- [x] Build the anatomy, coat, eyes, and snarling mouth.
- [x] Render and check the silhouette and expression.
- [x] Save and open the Blender model, record the option, and commit.

Checked: portrait, front, side, and wider-snarl renders. Fixed segmented legs and a displaced jaw pivot found in the first render. The model has a 30-frame jaw preview, separate studio collection, and embedded material colors. No running rig, game export, or in-game performance check in this pass.

## Revision 2: lean, ragged, mean (2026-10-09)

Rex: "make the animations as good as possible... Also the coyotes." The revision 1 coyote read as a smooth pale toy with rabbit ears, and every coyote on the road galloped in step.

Source: `scripts/blender/make_coyote_v2.py` rebuilds `art/models/coyote/coyote.blend` (no Blender app needed: `python3 scripts/blender/run_bpy.py - scripts/blender/make_coyote_v2.py -- [--quick] [--fur]`). Revision 1 is kept as `art/options/coyote/coyote-v1.blend`; its study renders stay in `art/options/coyote/blender-study/`.

What changed in the model:

- Anatomy: deeper keel, pinched waist, bony shoulder blades and hips, a thick neck ruff, thinner legs with a real elbow and hock, narrow paws with toes and claws, a longer narrower muzzle with a heavy brow and snarl wrinkles, big pointed ears tipped back and out, a bushy low tail.
- Face: black lips curled up off two 8 cm upper fangs, dark eye mask, amber eyes with a glint, dark angled brows, tear lines, a dark stripe up the nose, black nose with nostrils, dark mouth lining and tongue.
- Coat: one vertex-colored material for the whole hide (`tint()` in the script): grizzled gray-brown saddle with dark guard-hair speckle, cream throat, chest, belly and lower muzzle, rust legs and ear backs, darker crown, black tail tip. Nose, lips, claws, pads, brows and ear skin use the same material with fixed colors, so a moving part is one draw call.
- Ragged outline: `<part> tufts` objects, small four-sided spikes laid along the fur flow (hackles, ruff, cheeks, chest, belly fringe, haunch, tail brush). The exporter keeps them whole and decimates only the smooth hide under them.
- `Pivot <part>` empties mark the joints, including new ones for both ears and a second tail link. `export_game_pickup.py` reads them, and falls back to the old fixed joints for the revision 1 file.

What changed in the gallop (`gallop()` in `scripts/blender/export_game_pickup.py`): a rotary gallop with footfalls at 0, 0.10, 0.50 and 0.60 of the 0.45 s stride and a 36% stance, legs sweeping on the ground and folding in the air (elbows back, hocks forward), the body rising 4 cm in the stretched suspension and pitching 0.08 rad, the head steadying against the body with a bob, ears pinned back and fluttering, two tail links streaming with lag, and the jaw snapping shut once a stride.

In the game (`makeCoyote` in `GameScene.swift`): each pooled clone restarts its "run" players at a random offset and pace (0.9 to 1.1), scales 0.95 to 1.05 with the nose kept at z = 0, bobs a little at a period that does not divide the stride, and leans its head toward the cat through a 30% `SCNLookAtConstraint`. The PRD's "coyotes gallop in step" gap is closed.

Export: 25,724 triangles (budget 28,000), 20 geometry groups (was 30), 15 moving parts (was 12). Materials: coat, amber iris (with emission so the eyes read down the road), ivory teeth, dark mouth. `scripts/blender/preview_game_export.py` renders the exported JSON posed at any stride phase, which is the check to run where there is no Mac: `art/options/coyote/v2/game-*.png` and `side-*.png` are those, next to the Cycles renders of the source (`portrait`, `front`, `side`, `game-view`, `snarl`).

Not done here: the Swift step of `scripts/build_art.sh` (writes `coyote_run.scn`), `swift scripts/check_game_art.swift`, `scripts/e2e_visual.sh`, and the phone check. They need a Mac. `build_art.sh` now falls back to the pip `bpy` module when Blender.app is missing.
