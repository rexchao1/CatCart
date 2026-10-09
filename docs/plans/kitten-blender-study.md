# Kitten Blender study

Goal: make an editable Blender art option based on Rex's cat photo, with renders we can refine together.

Constraints: dove-gray British Shorthair, round cheeks, small ears, sitting pose. Keep the photo outside the repository and external services. Keep the current game model until Rex chooses this option.

Done when: the Blender file and front and rear renders are saved in `art/options/kitten-study/`, visually checked, and opened in Blender.

- [x] Read the PRD, 3D plan, existing kitten builder, and reference photo.
- [x] Build the first study with studio lighting and a soft gray coat.
- [x] Render and inspect face and rear silhouette.
- [x] Open the study in Blender, record the option, and commit the work.

Checked: Blender 5.2 rendered all three views; face and rear silhouette inspected; saved file opened in Blender. No game build or device check, since the live model is unchanged. This is a stylized first take for Rex to review.

## Revision 2: natural proportions

Rex rejected the toy proportions and asked for a much more realistic likeness on 2026-10-03. This revision replaces the oversized head and button eyes with a new anatomical study. The live game stays unchanged during review.

- [x] Build a longer seated torso, distinct front legs, smaller head, and cupped ears.
- [x] Add inset eyes, a short feline muzzle, fine whiskers, and directional short fur.
- [x] Render and inspect the new study against the photo, then open it in Blender.
- [x] Record the option and commit the files.

Revision 2 checks: three Blender renders inspected, including face, tail tip, and ear backs. Saved as a separate option. The face still needs likeness review; the study is not rigged or tested in the game.

## Revision 3: into the game

Rex saved the study as `art/models/kitten/cat.blend` and asked for it in the game on 2026-10-03.

- [x] `scripts/blender/export_kitten.py`: drop studio and strand fur, decimate to about 23k triangles, split into the animated parts, new tail held up over the box.
- [x] `scripts/build_kitten.swift`: new coat, eye, ear, and nose colors; reads either Blender script.
- [x] Old cartoon kitten kept as `art/options/player/kitten-cartoon.scn`.
- [x] Checked: offscreen previews (front, side, run camera) and simulator screenshots of the home screen and a run through all four worlds.

Not checked: frame rate on a real iPhone. The fur look is gone in the game (flat shading); a painted fur texture is the next step if it reads too smooth.

## Revision 4: cuter, and real fur in the game

Rex, 2026-10-08: "make the cat a lot cuter and more realistic. It looks like a marshmallow right now." In the game she was one smooth gray shape under flat light: no fur, no creases, small dark eyes. Revision 4 is a new study, `scripts/blender/make_kitten_v3.py`, saved over `art/models/kitten/cat.blend` (revision 2 stays in `art/options/kitten-realistic-v2`, and its game model in `art/options/player/kitten-v2.scn`).

- [x] Face: rounder British Shorthair cheeks and whisker pads, a short muzzle, big round golden eyes a little low and wide, a painted iris (fibers, dark rim, wide pupils, the upper lid's shadow), two catchlights, a lilac-pink nose, a soft mouth, longer whiskers.
- [x] Small round-tipped ears set wide, pink inside. Chunkier legs, round paws with four toes. A slightly fuller chest.
- [x] Coat painted in the .blend as a color attribute (paler muzzle, chin, and chest; a touch darker on the crown, back, and tail) plus a fur length attribute.
- [x] Export to JSON instead of USD (`export_kitten.py`), like the food and coyote: per-part geometry, the painted colors darkened where light can't reach (rays cast from every corner of the coat), and the direction the fur lies.
- [x] Shell fur in the game (`build_kitten.swift`): the coat drawn 8 more times, each pushed out a little further and combed along the fur, each throwing away all but the middle of a fine grid of tufts. It gives her a fuzzy outline and a plush coat.
- [x] Cuter idle on the home screen: a curious head tilt, breathing, and slow cat blinks.
- [x] Checked in the iPhone simulator: home screen face, run camera from behind, all four worlds.

Follow-up the same day (Rex: "make its eyes smaller and its collar tighter"):

- [x] Eyes about 17% smaller across (half width .058 to .048, dome .024 to .02), catchlights scaled with them. The first take is kept in `art/options/kitten-cute-v3` and `art/options/player/kitten-v3-big-eyes.scn`.
- [x] Collar moved 2.5 cm up her neck, to where it's narrowest under her jaw, and fitted to her: `add_collar.py` casts rays around her neck at three heights and sits the strap 2 mm outside the outermost surface, instead of a fixed oval that stood 1.5 cm off the back of her neck. The bell is pushed forward to clear her chest. The fur under the collar is short, in a band that tilts with it.

Pipeline: `make_kitten_v3.py` (study, renders) → copy to `cat.blend` → `scripts/build_kitten.sh` (export plus Swift build) → `CatCart/Models/cat_kitten.scn`. `swift scripts/check_game_art.swift` checks the parts, fur, and eyes.

Numbers: 24k triangles of kitten (as before) plus 8 fur shells over her coat (about 128k triangles, 40 draws, no shadows). Her head still tops out at 1.68 m sitting and about 1.25 m ducked, so the duck heights hold.

Not checked: frame rate on a real iPhone with the fur. If it costs too much, the lever is fewer shells (`furShells`) or a lighter coat mesh for the shells.

## Revision 5: real British Shorthair anatomy

Rex, 2026-10-08, looking at revision 4: "The cat has to look a lot more realistic, more cute." From the run camera (behind and above) she was still one smooth shape: a ball head on a cylinder neck, no shoulders, a pinched waist, flat ears. Revision 5 is a new study, `scripts/blender/make_kitten_v4.py`, saved over `art/models/kitten/cat.blend`. Revision 4 stays in `art/options/kitten-cute-v3b` as the fallback; `make_kitten_v3.py` still builds it.

- [x] Face: jowls under the cheeks (the chipmunk look that makes a BSH face a circle), a short broad muzzle block with a gentle stop under the eyes, a slightly wider nose, whisker-pad dots at the whisker roots, a rounder chin, a faint pale ring around each eye.
- [x] Eyes: same size as revision 4 (Rex's call). Deeper painted iris: finer and coarser radial fibers with dark crypts between them, a brighter jagged collarette, a wider dark limbal ring, bigger soft pupils, a stronger upper-lid shadow and a faint glow low in the eye. A furred upper-lid fold over each eye so it sits under a brow.
- [x] Ears: a wider base narrowing to a round tip, tipped out 12 degrees (was 10) and 2 cm thick (was 1.6) so they read plush instead of as plates, the pink showing from the front and the darker-painted backs from behind, five pale furnishings growing out of each bowl (`Left/Right ear furnishing`, exported on the ear so they flick with it).
- [x] Body: a neck ruff, shoulder blades, a filled-in cobby back (no waist), a round rump, bigger haunches, four toe bumps on each front paw. The tails are thicker, and their fur the longest on her.
- [x] Coat paint: darker crown with a faint stripe between the ears, darker ear backs, back, spine line and tail; paler muzzle, chin, bib and belly; a faint dusty-lilac sheen in the study material. Fur length: longest on the ruff, bib, cheeks and tail.
- [x] The study renders a fifth view, `game.png`, from the run camera's angle (behind and above, `docs/plans/camera.md`), so the back of her head and shoulders can be judged where the game sees them.
- [x] `scripts/blender/run_bpy.py`: runs any of the Blender scripts with the `bpy` Python module on a machine without Blender.app; `scripts/build_kitten.sh` falls back to it.
- [x] `export_kitten.py`: budgets and thicknesses for the new objects (ear furnishings, upper lids, whisker dots). Everything else, including the part names and pivots the game uses, is unchanged.

Numbers (export of the study): 25,452 triangles of kitten (was 24,136) plus the 8 fur shells over her coat; the painted fur length now reaches 1.57 on the bib (was 1.45), so the top shell stands about 3.3 cm off her chest in the game. Her ear tips top out at 1.001 m in the model (was 0.995), her skull at 0.967 (was 0.962), so she still sits with her head at about 1.68 m in the game; width 0.333 m (was 0.324). The duck heights in `docs/plans/duck.md` hold. Part pivots moved under 5 mm.

Not checked here: the Swift step (`build_kitten.swift`) and the iPhone simulator. This revision was built on a Linux box with the `bpy` module; the Mac runs `scripts/build_kitten.sh` and `swift scripts/check_game_art.swift`.
