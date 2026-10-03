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
