# Plan: smooth frame rate

Goal: the run never stutters. Rex noticed small lags. The simulator holds 60 fps on average, so the lag is short hitches plus phone-only costs, not a slow game.

Branch `perf-smooth`, in the worktree `.claude/worktrees/perf-smooth`.

## Constraints

- No change to look, feel, or rules, except slightly softer scenery shadows (scenery stops casting real shadows onto the road).
- Keep the teaching comments and the one-game-file shape.

## Done when

- A frame-time log (`CATCART_PERF=1`) reports average, worst frame, and every hitch with what spawned just before it.
- Nothing is built for the first time during a run: tree sizes, coyotes, food, road slices, and puffs all exist before the first tap.
- A cat tree costs a handful of draw calls instead of about 40.
- Shadows are cheaper: one cascade, and scenery does not cast.
- Before and after numbers from the simulator are written below. Phone numbers too once Rex plugs in his iPhone.

## Steps

| # | Step | State |
|---|---|---|
| 1 | Frame-time log behind `CATCART_PERF=1` and `scripts/perf_run.sh`; baseline numbers in the simulator | done |
| 2 | Build everything up front: every tree size, enough coyotes and food for the busiest waves, spare road slices, reusable puffs, sky pictures; have SceneKit prepare them before the run | done |
| 3 | Merge each cat tree's posts, cubbies, roof and base into one mesh (pom-pom and blob shadow stay separate) | done |
| 4 | Cheaper shadows: forward mode, one cascade out to 45 m, road and scenery do not cast | done |
| 5 | After numbers and screenshots of all four worlds done; phone check waits for Rex's iPhone | in progress |

## Numbers

Baseline, simulator (iPhone 17 Pro, 2026-10-03): 60 fps average. 311 to 614 draw calls, 364K to 562K triangles per frame. House world with cat trees is the worst for draw calls.

Hitches before (simulator, `scripts/perf_run.sh`): 33 to 50 ms stalls in the first seconds of a run, each right after a first-time build ("built tree14, built food" at 1.8 s and 4.0 s in house; "built tree24, built coyote" at 121 s with `CATCART_TIME=120` in city). Steady frames were 16.7 ms between them.

After step 2: zero frames over 25 ms in 30 s of house and 50 s of hard city. SceneKit's prepare of all pooled models takes 80 to 120 ms in the background on the home screen.

2026-10-05, tall trees and ramps (`pacing-and-trees.md` steps 4 to 6): prepare reads 167 to 216 ms on the build just before them and 174 to 248 ms after, so most of the rise since step 2 came earlier. Pools now hold short trees 11 to 40 m, tall trees 12 to 38 m (4 each), and ramps 8 to 17 m per height (3 each). No hitches after a run's first frames with the new mixes forced back to back.

After steps 3 and 4, same simulator, side by side with the step 2 build, 9 stats-bar samples each:

| Run | Draw calls before | after | Triangles before | after |
|---|---|---|---|---|
| House, start of run | ~420 | ~285 | ~730K | ~390K |
| City, `CATCART_TIME=90` | ~555 | ~340 | ~565K | ~350K |

Waves are random, so single samples swing by 150 either way; the averages are what count. Still zero hitches in house and hard farm. Home screen, city, jungle, and house look the same as before in side-by-side screenshots, including the cat tree and the shadow under the cart. Farm was only checked after, and looks normal.

2026-10-08, kitten fur (`kitten-blender-study.md` revision 4) and power-ups (`power-ups.md`). Measured in the iPhone 17 simulator on a GitHub macOS runner, city with the pilot, from the stats bar, two samples each, with the old furless kitten built in the same run for comparison: 569 to 636 draw calls and 707K to 817K triangles with the fur, against 545 to 568 and 611K to 653K without. That matches the fur's 8 shells over her coat (129K triangles, about 40 draws, none in the shadow pass). That machine's frame rate swung from 22 to 60 fps in both builds, so it says nothing about speed; the phone check still decides. Power-up pickups are built up front (two of each), and the food pool grew to 60 for the rocket's sky trail.

Model weights at the start: kitten 23K triangles in 8 parts, coyote 24K in 30 animated parts, food can 6K in 8 parts, road slice 11K to 28K. If the phone still struggles after steps 2 to 4, the next lever is lighter coyote and food exports (a far-away version with fewer triangles).

## Open

- Phone check: plug in the iPhone, run from Xcode with the `CATCART_PERF=1` environment variable in the scheme, play a run, and read the `CATCART` lines in the console. The simulator uses the Mac's graphics chip, so it can't show heat or GPU limits.
- Each coyote is now 30 animated pieces (about 60 draw calls with its shadow), the biggest cost left on a busy screen.

- The game slows its clock when a frame runs past 1/30 s, so a hitch reads as slow motion. Left alone unless the log shows it matters.
