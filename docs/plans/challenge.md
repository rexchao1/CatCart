# Plan: a real challenge, with a score

Goal: the run plays like Subway Surfers. You have to steer, the road gets busy, speed squeezes your reaction time, and a good run is something to brag about with a score. It still starts gentle.

Asked by Rex on 2026-10-04. Builds on `difficulty.md` (the ramp and tiers) and `duck.md` (ducking and low things).

## Why it was easy

- Every lane of every obstacle mix could be survived by staying in it and jumping or ducking. Sitting in one lane and reacting was the best strategy, so steering never mattered. The test pilot never steers and survives forever.
- Each mix is small, usually one move, followed by 1 to 1.75 s of empty road. One decision every two seconds or so, never two moves to plan.
- All spacing stretches with speed, so the timing at 30 m/s is the same as at 17. Faster only looks faster.
- Timing is loose. She clears a coyote for 80% of her jump (a window of about 0.65 s). A coyote is a single point with no body. A lane change counts as done the instant you swipe, mid-slide.
- Food is never where grabbing it costs anything.

## Rex's calls (2026-10-04)

- Harder for everyone. No difficulty setting. Mom gets the same game.
- The "every lane survivable" rule goes. New rule below: there's always a way through, sometimes by steering.
- Runs are endless like Subway Surfers, with a score.
- Score has no multiplier.
- Glancing hits are stumbles, not crashes. The chaser is a green plastic spray bottle.
- Top speed goes up a little, and the ramp reaches it a little sooner.
- No steering test autopilot (Rex: overengineering). Each new mix is checked by hand against the fairness rule, and Rex plays it. The existing pilot stays as is for screenshots.
- Not doing: a measuring harness with a human-like bot, crash logging, a solver that proves fairness, intensity tied to worlds, extra input buffering, or moving the medium and hard mixes earlier.

## Rules

### Fairness, new version

- Every mix has at least one way through, from any lane, using at most one lane change plus jumps and ducks, with at least about 0.5 s to make the lane change.
- Never block all three lanes with no jump, duck, or ride out (unchanged).
- Low things never stand beside the middle of a tree (unchanged).
- The first 15 s stay easy mixes only. Medium joins at about 15 s and hard at about 40 s, as now, pinned to seconds so the faster ramp doesn't pull them earlier.

### Crash or stumble

- Crash: running straight into a coyote, a low thing, or a tree front in your lane. Unchanged.
- Stumble: a glancing hit. Bumping the side of a cat tree while steering (today a free bump). Clipping a coyote or low thing in the lane you're leaving or entering while the cart is still sliding over.
- After a stumble, the cart wobbles and a green plastic spray bottle hops along right behind her for about 4 s, then falls back and leaves.
- A second stumble while the bottle is there means you're caught: the bottle sprays her, and it counts as a crash with the usual "Oh no!" panel.

### Score

- The score counts up as you run, and each can of wet food adds a bonus. Exact numbers get tuned while building (start: 1 point per meter, 25 per can).
- Food no longer adds bonus meters.
- The heads-up display shows score and food. The death panel shows score and food big, plus the best score. "New best!" is for the score.
- Best score is saved on the phone under a new key. The old best distance is not carried over.

### Speed

- 17 m/s at the start, up to 34 (was 30), reached at about 2.5 minutes (was 3). Same shape: climbs fast early, then settles.
- Spacing inside a mix grows more slowly than speed, so a faster run really leaves less time to react. Same-lane hazards still keep enough time for a jump to land.

## Constraints

- PRD locks that stay: the cat, the La Croix cart, coyotes you jump, wet food, cat-tree trains, four worlds at about 10 s, one thumb, no on-screen buttons.
- Everything spawned mid-run is built before the run (`performance.md`). The spray bottle is built up front and reused.
- Teaching comments stay. All of it lives in `GameScene.swift` and `Hud.swift`.
- Each mechanic's player-facing rule goes into `docs/prd.md` in the same commit as the code.

## Done when

- Every mix is checked by hand against the fairness rule, and each new one is seen at top speed with `CATCART_WAVE` and `CATCART_TIME=200`.
- Rex finds it hard and fair on his phone.
- A stumble brings the spray bottle, a second one while it chases is a crash, and a single stumble is survivable.
- The score shows during the run, on the death panel, and as the best on the home screen.
- No new hitches with `CATCART_PERF=1`.
- The PRD describes the new fairness rule, stumbles, the bottle, the score, and the new speeds.

## Steps

| # | Step | State |
|---|---|---|
| 1 | Speed 17 to 34 over about 2.5 min; mix spacing grows slower than speed; tier entry pinned to 15 s and 40 s | done |
| 2 | Tighter timing: coyotes get a body length, the clear part of a jump gets shorter, a sliding cart counts in both lanes | done |
| 3 | Stumbles and the spray bottle: model built in code, hop-along chase, second stumble catches her | done |
| 4 | Mixes that need steering, food on the risky line, new fairness rule, each mix checked by hand | done |
| 5 | No breather between mixes in the hard tier, so they chain | done |
| 6 | Score in the heads-up display, death panel, home screen, and saved best | done |
| 7 | Simulator check: new mixes at top speed, perf log, screenshots of the bottle and the score; PRD update | done |

## How it was built, 2026-10-04

- Blocked lane: a coyote under a low thing, in one lane (`b(lane, ahead)` in the mix list). No new model: the coyote is 1.14 m tall and fits under the 1.38 m clearance.
- Tighter timing: a coyote counts as 1.5 m long and must be cleared the whole time it's beside her; clear height is 0.8 m rising to 1.0 m. A lane change counts once the cart crosses the line between lanes (`bodyLane`). The cart slides over in about 0.04 s, so this mostly matters for a swipe right as something arrives.
- Spacing: mix distances scale by (speed / 17) to the 0.6 power. Trees still scale fully, and anything behind a tree moves back by the extra length.
- Joins: before placing a mix, every lane keeps 19 m (24 m coyote to low thing, scaled) after the last hazard already in it; if not, the whole mix moves back.
- Gaps: 1.75 s shrinking with the ramp; from 40 s, 1.05 s minus 0.65 x ramp, never under 0.4 s.
- Pools: 16 coyotes, 24 cans, 12 low things per world.

## Result, 2026-10-04 (simulator, iPhone 17 Pro)

- Screenshots: blocked lanes read as coyotes under the scaffold; the bottle hops behind her right side with the trigger showing, and leans over the tipped cart when it catches her; score shows in the pill and on the panel with "New best!".
- The non-steering pilot (crashes on) crashed on a blocked-lane mix (22) and survived 20 s of plain coyotes (0) at 20 s into the ramp.
- The pilot survived ~22 s each of the same-lane hard mixes 24, 27, 32, 34, 35 at top speed (`CATCART_TIME=200`), forced back to back, so the joins held.
- Perf: 60 s at top speed in the city, and the zigzag (39) and gate (40) mixes forced in the house: no mid-run builds, no hitches past the launch frame.
- Not yet played by hand or on a phone. Tuning (gaps, clear height, chase time, food points) waits on Rex playing it.

## Round 2, 2026-10-05 (Rex: still too easy, too spread out, start sooner, more obstacles)

- The road is filled with mixes from 40 m out when a run starts, so the first coyote arrives about 2 s after the tap instead of about 9.
- Medium mixes at 8 s (was 15), hard at 25 s (was 40). Hard mixes weigh in sooner (0.4 + 1.3 x ramp).
- Gap between mixes: 0.9 s at the start, down to 0.25 s (was 1.75 s, down to 0.4 s from 40 s).
- Spacing inside a mix grows with the square root of speed (was the 0.6 power): same-lane coyotes are about 0.8 s apart at top speed.
- Every mix has two or more obstacles; the food-only mixes are gone. 46 mixes, including two new hard ones with blocked lanes (a blocked middle with coyotes beside it, then the reverse; a blocked lane that walks across the road).
- Pools: 22 coyotes, 28 cans, 14 low things per world.
- Checks: the non-steering pilot (crashes on) survived ~14 s of each of the 36 mixes without a blocked lane, forced back to back at top speed. Perf: 75 s from the start and the busiest blocked-lane mixes at top speed, no mid-run builds. One extra 33 ms frame at the start of a run, from filling the road at once; it lands during the camera swoop after the tap.
- Not yet played by hand.
