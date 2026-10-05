# Cat Cart

iPhone portrait runner game. SpriteKit. One scene.

Before you change look, feel, art, or mechanics, read `docs/prd.md`. That file is the product. Code follows it.

If a request fights the PRD, ask. Do not silently replace a locked call (the cat, the La Croix cart, coyotes you jump, wet food, cat-tree trains, four worlds at ~10s).

Spare art lives in `art/options`. Rex deletes what he does not want. Live defaults are the imagesets in `CatCart/Assets.xcassets`.

Plans for multi-step work live in `docs/plans/`. Read `docs/plans/3d-world.md` before touching the scene, camera, worlds, or art pipeline. It tracks the move to a 3D world.

Read `docs/plans/difficulty.md` before changing speed, jump tuning, or obstacle mixes. It explains the difficulty ramp and the fairness rule.

Read `docs/plans/challenge.md` before changing obstacle mixes, crashes, stumbles, the score, or speed. It has the fairness rule that replaced "every lane survivable" and tracks the work to make runs a real challenge.

Read `docs/plans/duck.md` before changing ducking or the low things you duck under. It has the heights that make the duck fair.

Read `docs/plans/performance.md` before adding models, effects, or anything spawned mid-run. It says what must be built up front and how to measure hitches with `CATCART_PERF=1`.

## Food and coyote assets

The editable sources are `art/models/food/wet-food.blend` and `art/models/coyote/coyote.blend`. After editing either, run `scripts/build_art.sh`, then `swift scripts/check_game_art.swift` and `scripts/e2e_visual.sh`. The export strips the studio and strand fur and adds the coyote gallop. It never saves over the Blender sources.

Xcode builds use the committed `CatCart/Models/wet_food.scn` and `coyote_run.scn`; Blender is not needed for a normal app build.
