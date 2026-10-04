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
| 3 | Merge each cat tree's posts, cubbies, roof and base into one mesh | todo |
| 4 | Cheaper shadows: forward mode, one cascade, scenery does not cast | todo |
| 5 | After numbers, screenshots of all four worlds, phone check | todo |

## Numbers

Baseline, simulator (iPhone 17 Pro, 2026-10-03): 60 fps average. 311 to 614 draw calls, 364K to 562K triangles per frame. House world with cat trees is the worst for draw calls.

Hitches before (simulator, `scripts/perf_run.sh`): 33 to 50 ms stalls in the first seconds of a run, each right after a first-time build ("built tree14, built food" at 1.8 s and 4.0 s in house; "built tree24, built coyote" at 121 s with `CATCART_TIME=120` in city). Steady frames were 16.7 ms between them.

After step 2: zero frames over 25 ms in 30 s of house and 50 s of hard city. SceneKit's prepare of all pooled models takes 80 to 120 ms in the background on the home screen.

Model weights at the start: kitten 23K triangles in 8 parts, coyote 24K in 30 animated parts, food can 6K in 8 parts, road slice 11K to 28K. If the phone still struggles after steps 2 to 4, the next lever is lighter coyote and food exports (a far-away version with fewer triangles).

## Open

- The game slows its clock when a frame runs past 1/30 s, so a hitch reads as slow motion. Left alone unless the log shows it matters.
