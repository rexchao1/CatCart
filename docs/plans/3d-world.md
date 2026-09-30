# Plan: 3D world, flat cat

Goal: make Cat Cart feel seamless like Subway Surfers. The road, buildings, and cat trees become real 3D in SceneKit. The cat, coyotes, and food stay as the current 2D pictures, turned to face the camera.

Decided by Rex on 2026-09-30, over "stay 2D and polish" and "full 3D characters now".

## Why

Screenshots of the 2D build (every world) showed:

- Side walls are one texture stretched on flat slabs. They read as a canyon, not a street.
- Four art styles at four scales: painted sky, photo-real cat, cut-out buildings, flat floor tiles.
- Coyotes and food are specks until the last half second. The cat tree reads as a far tower.
- Floor moiré in city and house. White lane lines look like debug.
- No shadows. Everything floats.

Most of the Subway Surfers look is real depth: the road bending down over the horizon, fog, buildings with sides. That needs 3D.

## Constraints

- Every locked call in `docs/prd.md` stays: the cat, the La Croix cart, coyotes you jump, wet food, cat-tree trains, four worlds at ~10s, the controls, the jump hang and slam.
- SceneKit, not RealityKit. SceneKit has built-in fog, a curved-world bend as a short shader-modifier string, and `overlaySKScene` so the SpriteKit HUD carries over. Apple soft-deprecated it at WWDC25 (maintenance only, no removal planned). Fine for a gift app. RealityKit is the move if SceneKit ever breaks.
- Cat, coyote, and food art stay 2D until Rex locks the cat stills (PRD rule).
- World art from CC0 kits only (Kenney, Quaternius), so no license questions. Keep source files in `art/`.
- Keep teaching comments. One game file plus the HUD overlay, not an engine.

## Done when

- The PRD "done when" list holds in the 3D build.
- A run through all four worlds reads as one continuous place in simulator screenshots.
- Coyotes, food, and trees are readable well before they arrive.
- Every object has a shadow and nothing shimmers.

## Steps

| # | Step | State |
|---|---|---|
| 0 | Project in Git, 2D game and this plan saved as the first commit | done |
| 1 | Test build. Skipped as a separate step: Rex asked for the whole thing in one go, so the real build answered it. The soft cat reads fine in the Kenney cartoon world. | done |
| 2 | Game rules in 3D coordinates, HUD via `overlaySKScene`, input queued to the render thread. Tree side-bump rule added. | done |
| 3 | Cat tree as a real 3D train: carpeted roof, sisal posts, cubbies, pom-pom, lengths 11/14/17 m. | done |
| 4 | Four worlds from Kenney kits (`Scenery.swift`, `CatCart/Models`). Drive-into world change with sky, fog, and light blend (Rex OK'd, PRD updated). | done |
| 5 | Feel polish: trailing camera, lane roll, landing squash, dust, speed FOV, tip-over crash, shadows. Wheel spin waits for 3D cart. | done |
| 6 | 3D kitten, cart, and coyote. Built in Blender by script instead of Meshy: kitten from Rex's photos (`scripts/blender/make_cat.py` + `scripts/build_kitten.swift`), coyote from an NPS public-domain photo (`make_coyote.py` + `build_coyote_scn.swift`, baked 0.45 s gallop). Cart built in code (`KittenCart.swift`) with real La Croix lettering from `scripts/make_cart_textures.py`. Wheels spin, tail sways, ears flick, eyes blink, head leans into turns. | done |
| 7 | Real home screen: camera in front of her face, title, paw button, best pill; tap swoops the camera behind her into the run. Arc jump replaces the timed hang. | done |

Check after each step: `scripts/e2e_visual.sh`, screenshots reviewed.

## Open

- Not checked on a real iPhone yet: frame rate with shadows on, and how the swipes feel. Simulator only so far.
- Rex's cat photos are reference only. They stay out of the repo and out of any external service.
- Coyote clones gallop in step. Staggering them means copying each part's animation with its own `timeOffset` (untested).
- House rug toned down and cat tree carpet warmed (2026-09-30). New app icon takes in `art/options/icon`.

- Art style: low-poly cartoon kits next to a soft, realistic cat. Step 1 answers it. If they clash, the fallback is restyling the kits (flat-color toon shading) or regenerating the cat softer.
- World-change style (step 4).
- Camera numbers. Starting guess: field of view about 65 degrees, camera about 3.5 m up and 6 m back, tilted down about 20 degrees. Tune by eye.

## Research notes

- SceneKit status: https://developer.apple.com/videos/play/wwdc2025/288/
- Curved world: push each vertex down by k times distance squared in a geometry shader modifier. Widen culling bounds.
- Asset kits: Kenney City/Furniture/Nature kits, Quaternius nature and farm packs (all CC0, GLB/FBX). Convert with Reality Converter or Blender to USDZ/SCN.
- USDZ keeps one animation timeline. Multi-clip rigs go end to end in Blender's NLA editor, then split by time in code. Only matters at step 6.
