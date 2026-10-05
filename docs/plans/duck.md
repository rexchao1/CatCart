# Plan: duck into the box

Goal: a third move next to jumping and changing lanes. Swipe down on the ground and the kitten sinks into her La Croix box for a moment, so low things pass over her. Each world gets one low thing to duck under.

Asked by Rex on 2026-10-04. He said no leaping coyote: coyotes stay jump-only.

## Rules

- Swipe down on the ground: she ducks for 0.45 s. Only her ears, the top of her head, and her tail tip show over the rim. Then she pops back up with a little bounce. Swiping down again restarts the 0.45 s.
- Swipe down in the air: she only drops fast (as before ducking existed). No duck on landing.
- Swipe up while ducking: the duck ends and she jumps.
- Lane changes keep the duck going.
- A low thing in her lane crashes her unless she is ducked on the ground. Jumping into it is a crash too.
- Ducking does nothing against coyotes or the front of a cat tree.
- Low things sit on the ground lanes only, never over a cat tree roof, for now.

## Low things, one per world

| World | Low thing |
|---|---|
| City | Construction scaffold: two posts and a striped plank across the lane |
| Jungle | A mossy log lying across two stumps |
| House | A wooden table, with legs at the lane edges |
| Farm | A clothesline between two posts with a sheet hanging down |

Each has an open gap under it down to the road, a shadow strip under it, and its bottom edge just above the box rim.

## Constraints

- PRD locks stay: coyotes are jumped, trees are ridden, four worlds at ~10 s, one thumb, no buttons.
- Fairness rule becomes: every lane of every mix can be survived by staying in it and jumping or ducking. The test pilot learns to duck.
- Low things join with the medium mixes (about 15 s), so the first 15 s stay as they are.
- Everything is built before the run (performance plan). Low things are merged into one mesh like the cat tree.
- The kitten's look is not reworked. The duck moves her whole model down inside the box.
- First time only, a one-line "Swipe down to duck" hint shows as the first low thing comes. It stops once she has ducked under one.

## Done when

- She ducks, peeks, and pops up in the simulator, and the low things read as "go under" in all four worlds.
- Pilot without god mode survives 60+ s from the start and from `CATCART_TIME=200`.
- No new hitches with `CATCART_PERF=1`.
- PRD describes the move, the low things, and the new fairness rule.

## Steps

| # | Step | State |
|---|---|---|
| 1 | Duck move: input, timer, landing queue, kitten sinks in the box with a spring | done |
| 2 | Low things: four models, pooled per world, picked by the world they spawn in | done |
| 3 | Crash rule, mixes in the medium and hard tiers, pilot ducks | done |
| 4 | First-time hint | done |
| 5 | Simulator check: screenshots of each low thing, pilot survival, perf log | done |
| 6 | PRD update | done |

## Heights (body meters times the cart's 1.25 scale)

- Box rim 0.96 m. Sitting, her head tops out at about 1.68 m.
- Ducked, she sinks only 0.08 (to the box floor) and her body node squashes to 58% in y. Head and tail sit in holders that scale back, so they keep their shape and their turns don't skew. Her head tops out at about 1.25 m, eyes at the rim.
- Sinking her whole model deeper looked simpler but pushed her bottom out under the box, visible between the back wheels from the run camera. That's why it squashes instead.
- Every low thing's underside is `lowClearance` = 1.38 m. Changing the kitten model means rechecking these numbers.
- The higher jump (2.6 m peak, 2026-10-05) and the 2.0 m short tree roof changed none of these. A low thing is still a crash at any height unless she's ducked, so a jump never goes over one, and low things still stand only on the ground lanes.

## Result, 2026-10-04 (simulator, iPhone 17 Pro)

- Pilot with crashes on: 75 s from the start and 65 to 75 s from `CATCART_TIME=200` (city and house), no crash. Each new mix forced with `CATCART_WAVE` (17 to 20, 29 to 32) for 30 s at top speed, no crash.
- Perf: forcing the three-low-thing mix back to back ran out of the 6 pooled per world and built one mid-run (383 ms). Fixed with 9 per world and shared low-thing materials; reruns show no hitches past the launch frame. The same runs caught a 333 ms stall from a fourth tree of one size, so trees now pool 4 per size.
- Screenshots: all four low things read as "go under" up close and from the far road; the ducked pose shows ears and head top over the rim.
- Not yet played by hand or on a phone. The hint was seen once and retired after the first duck, as designed.

## Round 2, 2026-10-04 (Rex's feedback)

- Duck 0.8 s was way too long: now 0.45 s. The pilot ducks 6 m out, which is 0.35 s at the start and 0.2 s at top speed.
- Swipe down in the air no longer queues a duck; it only lands her. A low thing after a coyote in the same lane now gets 24 m (1.4 s) instead of 19, so a late jump can land and still swipe to duck.
- Obstacles floated over the far road and dropped onto it as they came close. Cause: the cat tree and low things are merged meshes, and a merged mesh gets its materials after `applyLook` ran, so they had no bend or fog. `applyLook` now runs on the pieces before merging; screenshots show them rising over the hilltop on the road. Coyotes and food were already right.
- Recheck: pilot with crashes on, 75 s from the start, 70 s at top speed (jungle), and mixes 17, 29 to 32 forced for 30 s each at top speed, no crash. One unexplained 333 ms stall in one top-speed jungle run did not come back in three repeats.

## Round 3, 2026-10-05 (Rex's feedback)

- A jump that carries her above `lowTop` (2.0 m) now clears a low thing, so ducking is not the only answer. Tops of the house vase and farm clothesline were lowered to fit under 2.0 m. Blocked lanes (coyote under a low thing) can be jumped too now.
- Jump airtime is 0.9 s to 0.78 s (was 0.8 to 0.62) so the jump looks longer. Not yet rerun through the pilot at top speed.
