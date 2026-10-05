# Plan: hard sooner, more cat trees, and a calmer death screen

Goal: the run gets hard in the first 30 seconds instead of after a minute, cat trees become the star (more of them, side by side, tall ones, ramps up onto them), and dying never drops you into a new run by accident. The death panel shows what you did.

Asked by Rex on 2026-10-05, after playing round 2 of `challenge.md`. Builds on `challenge.md` (fairness rule, mixes, gaps) and `difficulty.md` (the ramp).

## Why it is still easy until about a minute

The felt difficulty is mostly speed, and speed follows `ramp`, which takes 150 s:

| Time | Ramp | Speed today |
|---|---|---|
| 8 s | 0.10 | 18.8 m/s |
| 30 s | 0.36 | 23 m/s |
| 60 s | 0.64 | 28 m/s |
| 150 s | 1.0 | 34 m/s |

The gap between mixes, the jump's quickness, the clear height, and how often hard mixes come all read the same `ramp`, so all of them are still mild at 30 s. Rex's "hard after about a minute" lines up with 28 m/s and a ramp near 0.64. Medium and hard mixes already join early (8 s and 25 s), but at 23 m/s with 0.65 s gaps they are easy to read.

Cat trees are about 30% of mixes (14 of 46), and only three put two trees side by side. Every tree has the same 1.5 m roof.

Any touch on the death panel restarts, and a swipe that was already in flight when she crashed counts as a touch.

## Rex's calls (2026-10-05)

- Too easy until a minute in. Make it hard sooner.
- More cat trees, more creative ones, like two side by side. They are fun.
- Taller trees, and ramps up onto some of them.
- A pause after dying so a stray tap doesn't start a new run, and the death screen shows your stats.

Follow-up the same day:

- Stats are just time and food.
- Raise the trees, and raise the jump to match: higher and faster, so the arc looks bigger. "I just want the animation higher." The timing stays the same.
- Build it with subagents.

## Rules

### Pacing

- The ramp reaches full in 75 s instead of 150 s, same shape (fast early, then settles). Today's one-minute run arrives at about 30 s.

  | Time | Ramp | Speed |
  |---|---|---|
  | 8 s | 0.20 | 20.4 m/s |
  | 20 s | 0.46 | 24.8 m/s |
  | 30 s | 0.64 | 27.9 m/s |
  | 45 s | 0.84 | 31.3 m/s |
  | 75 s | 1.0 | 34 m/s |

- Start speed stays 17 m/s, and the first 8 s stay easy mixes only (PRD: short gentle start).
- Past 75 s, so long runs still get harder: speed keeps creeping up 1 m/s every 30 s, to 38 m/s at about 3 min. The jump, clear height, and gaps stay at their full-ramp values; spacing inside a mix keeps growing with the square root of speed, so same-lane coyotes are about 0.75 s apart at 38.
- Hard mixes join at 20 s (was 25). Easy mixes thin out faster and settle at 15% weight (was 25%).
- Gap between mixes is unchanged as a formula (0.9 s down to 0.25 s), so it now shrinks twice as fast: 0.45 s at 30 s.

### A higher jump

- The jump peaks at 2.6 m (was 1.9). How long she's in the air doesn't change (0.8 s at the start down to 0.62 s), so she leaves the ground faster and gravity pulls harder. Every timing in the game stays the same; only the arc is taller.
- Everything measured against the jump scales with it (x 1.37) so it plays the same: clearing a coyote takes 1.1 m at the start and 1.37 m at full ramp (was 0.8 and 1.0), food hanging in the air sits at 2.0 m (was 1.45) and needs 1.23 m to reach (was 0.9).
- Low things, ducking, and coyotes keep their heights.

### Cat trees

- Trees show up in about half the mixes (today about 30%), and side-by-side trees are common from the medium tier on.
- Two heights:
  - Short tree: today's tree raised, roof at 2.0 m (was 1.5). A jump from the ground (peak 2.6 m) lands on it, as now.
  - Tall tree: roof at about 3.5 m, two stories of cubbies. A jump from the ground can't reach it, so its front is a crash, like a wall. You get up there by a ramp, or by jumping from a short tree's roof (that jump peaks at 4.6 m).
- From a tall roof you can step sideways down onto a short tree or the ground. Stepping sideways from a short roof onto a tall one is a bump and a stumble, unless you're high enough in a jump.
- Ramp: a carpeted slope, about 8 m long (stretched with speed like trees), climbing from the road to the front of a tree. Roll onto it in its lane and you ride up onto the roof with no jump. Jumping on a ramp works. Steering onto a ramp from the side works where it's still low (under about 0.5 m); higher up the side is a bump and a stumble.
- The camera already rises with the roof. Check that it still sees the road ahead from a tall roof; lower its rise for tall trees if it doesn't.
- The fairness rule from `challenge.md` holds. A tall tree with no ramp and no short tree before it counts as a blocked lane. A row of three short trees is allowed (a forced jump onto the roofs, used rarely). Low things still never stand beside the middle of a tree.

### New tree mixes (first ideas, each checked by hand)

- Twin trees: two trees side by side, different lengths, so one ends first and you step across to the other.
- Tree yard: three lanes of staggered trees. Ride them by hopping roof to roof as each one ends.
- Ramp up: a ramp onto a tall tree in the middle, coyotes in both side lanes. The easy way through is up.
- Staircase up: a short tree, then a tall tree right behind it in the same lane. Jump from the short roof to the tall one.
- Step down: a tall tree beside a short tree; leave the tall one early and drop onto the short one.
- Gap jump: two short trees in one lane with a coyote in the gap between them. Jump the gap roof to roof, or fall in and jump the coyote.
- Wall with a ramp: tall trees in two lanes, a ramp onto a tall tree in the third. Up is the only way through.
- Food along the roofs of all of these, so riding pays.

### Death pause and stats

- When she crashes, taps are ignored for 1 s. The panel still pops in at once, so you see your numbers during the pause.
- The "Dash again" button pops in when the pause ends, so you can see when tapping works again.
- A run restarts only on a fresh tap: a touch that starts after the pause and lifts without swiping. A swipe already in progress when she crashed, or any swipe on the panel, does nothing.
- The panel shows three big numbers across: score, food, and time survived (like 1:12), with best under them. No other stats (Rex, 2026-10-05).
- The home screen tap is unchanged.

## Constraints

- PRD locks stay: the cat, the La Croix cart, coyotes you jump, wet food, cat-tree trains, four worlds at about 10 s, one thumb, no on-screen buttons during a run, no difficulty setting.
- Changing the speed curve, tree heights, ramps, and the death panel all change PRD text. Each lands with its PRD update in the same commit.
- Tall trees, ramps, and the extra tree sizes are built before the run and pooled (`performance.md`). Tree pools are keyed by length and height; ramps by length and height.
- A tall tree and a ramp are each merged into one mesh after `applyLook` runs on their pieces, like today's tree.
- Teaching comments stay. Tree and ramp code stays in `GameScene.swift`, the panel in `Hud.swift`.
- The test pilot jumps and ducks but never steers, and it won't learn ramps or tall trees. New mixes are checked by hand and with `CATCART_WAVE` at `CATCART_TIME=200` in god mode.

## Done when

- At 30 s a run plays like today's run at one minute, and Rex says it gets hard soon enough.
- Trees are in about half the mixes, tall trees and ramps show up from the medium tier, and Rex finds them fun.
- She rolls up a ramp onto a tall tree, hops from a short roof to a tall one, steps down from tall to short, and crashes into a tall tree's front from the ground.
- After a crash, mashing the screen for a second doesn't start a run, a swipe in progress doesn't either, and a tap after the button appears does.
- The death panel shows score, food, and time, readable on an iPhone screen.
- The jump arc is visibly higher and lands at the same moment as before.
- No new hitches with `CATCART_PERF=1` in a 90 s run and in the busiest tree mixes forced back to back.
- The PRD describes the new speeds, tall trees, ramps, the death pause, and the stats.

## Steps

| # | Step | State |
|---|---|---|
| 1 | Pacing: 75 s ramp, speed creep to 38 after it, hard mixes at 20 s, easy floor 15%; PRD speed lines | done |
| 2 | Death pause: 1 s tap lock, drop queued input on crash, restart on a clean tap only, button pops in after the pause | done |
| 3 | Time on the death panel next to score and food; check the layout on screen | done |
| 4 | Higher jump (2.6 m peak, same airtime), clear height and air food scaled to match; short tree roof to 2.0 m. Per-tree roof height: each tree knows its roof; landing, riding, stepping off, side bumps, camera, dust, and shadow use the roof of the tree she's on | done |
| 5 | Tall tree model: two stories, built and pooled up front; crash on its front from the ground, mount from a short roof | done |
| 6 | Ramp model and rules: slope in front of a tree, roll up, side entry low or bump, pooled up front | done |
| 7 | New tree mixes (list above), more weight on tree mixes overall, each checked by hand against the fairness rule | not started |
| 8 | Simulator check: screenshots of a tall tree, a ramp, and the death panel; ramp and tall-tree moves seen with `CATCART_SWIPES`; perf log; PRD update | not started |

Result for steps 1 to 3 (2026-10-05, iPhone 17 simulator): speed logged at 20.4 m/s at 8 s, 24.9 at 20 s, 27.9 at 30 s, 31.3 at 45 s, 34 at 75 s, 35 at 105 s, 36 at 135 s, and 38 from about 195 s. Death pause driven with `CATCART_SWIPES` (two stumbles to crash, then `tap`, `press`/`release`, and swipes): a tap at 0.4 s and 0.5 s did nothing, a touch that began in the pause and lifted at 1.3 s did nothing, a touch held down through the crash and lifted 2.5 s later did nothing, swipes after the pause did nothing, and a tap after the pause restarted. The button showed at 1.0 s. Panel screenshots with 61 / 0 / 0:03, 2,480 / 18 / 1:12, and 12,345 / 123 / 12:34 all fit three columns; the longest shrinks all three numbers together and still reads. Time survived leaves out the `CATCART_TIME` head start (0:03 after starting at 200). `scripts/perf_run.sh` at 0 s and 60 s: steady 16.7 ms frames; two first runs each showed one stray stall with no spawn before it that did not repeat on a rerun. Not played by hand yet.

Steps 1 to 3 are small and can ship first so Rex can play the new pacing while the trees are built.

### Result, steps 4 to 6 (2026-10-05, simulator, iPhone 17 Pro)

Built:

- Jump peak 2.6 m, airtime unchanged. Clear height 1.1 to 1.37 m (follows `ramp`). Air food at 2.0 m, reached above 1.23 m. The camera bob in a jump went from 0.12 to 0.09 per meter and the shadow shrink and fade from 0.22 and 0.25 to 0.16 and 0.18, so both look as they did at 1.9 m. Slam down starts at 22 m/s (was 16) so it still feels quick from higher up. Low things and ducking unchanged.
- Each cat tree carries its roof (2.0 or 3.5 m) and its ramp length. `floorY` is the top under her (road, roof, or ramp slope where she is), and landing, riding, the hand-off to the next tree in the lane, stepping off sideways, side bumps, dust, shadow, camera, and roof food all read it.
- Who gets on what (`canReach`): rolling, she gets up a step of 0.5 m (the low end of a ramp from the side, never a roof). In a jump, short-tree heights use the old rule (above the clear height). A tall roof, or the high part of a ramp, needs her within 0.5 m of it, which only a jump from a short roof does. Level or higher is always fine: stepping down is a drop.
- Tall tree: roof 3.5 m, a carpet shelf halfway up, a second story of cubbies in the bays between the lower ones. One merged mesh like the short tree.
- Ramp: a carpeted wedge with sisal rope along both top edges, sliced along its length so the road's bend bends it. It hangs off the tree's front as a child of the tree's node, and the tree and ramp are one track item. She leans nose-up on the slope.
- Pools: short trees 11 to 40 m (4 each), tall 12 to 38 m (4 each), ramps 8 to 17 m for each height (3 each). That covers a 17 m tree at 38 m/s. A ramp at 38 m/s wants 17.9 m and gets 17.
- Mix syntax: `t(lane, ahead, length)` short tree, `tall(...)` tall tree, `ramp(t(...))` or `ramp(tall(...))` puts an 8 m ramp in front with `ahead` at its foot. Three provisional mixes at the end of `waves` (46 ramp up, 47 staircase up, 48 step down), marked for step 7 to rewrite.
- Also fixed: each cubby's doorway was half sunk in the road in front of every tree (the merge flattened it to its own offset). The doorways now sit on the cubbies.
- `CATCART_SWIPES` now prints a line per swipe and stumble with run time, lane, height, and the top she's on.

Checked:

- Swipes: roll up the ramp onto a tall roof and collect the roof food (46); short roof to tall roof (47, pilot); a jump from the road crashes into the tall front (47); steering onto a ramp from the side under 0.5 m gets on, at about 1.1 m it's a bump and a stumble; stepping right off a tall roof drops onto the short roof beside it (48, height 3.5 then 2.0).
- Pilot without god mode: 46 and 47 from the start and at `CATCART_TIME=200`; city at 200 on 7, 17, 26, 29, 31, 33, 34, 36; house from the start on 7, 17, 26, 46, 47, 48. No crashes. Mix 45 (blocked lanes) still crashes as it should.
- Camera (the open question below): rising half as much above a short roof put her head right over the road ahead on a tall roof. It now rises all the way, so a tall roof is framed like a short one, and the road ahead is in view.
- Screenshots in city and house: the ramp bends over the far hilltop with the road, the tall tree reads as a two-story tower with a flat roof, and the higher arc shows.
- Perf, `CATCART_PERF=1`: house 30 s, city from 120 s for 40 s, and 46, 47, 48 each forced back to back for 22 s. No hitch after the first frames of a run (the same 33 to 67 ms launch frames as the build before). Prepare takes 174 to 248 ms; the build before this took 167 to 216 ms in the same runs, so the extra pools cost little. Draw calls: mix 16 forced in house reads about 600 before and after; the ramp and staircase mixes read about 670 to 720 (a tall tree, roof food, and four coyotes); 48 at top speed in city reads about 450.

Not checked: by hand on a phone, and the new mixes are placeholders, not the step 7 set.

Built with subagents, each in its own worktree and simulator: one for steps 1 to 3, one for steps 4 to 6 at the same time, then one for step 7 on top of both. Step 8 is the merged check.

## Open

- Whether 75 s is the right ramp length is a feel call. If 30 s is now too hard, 90 s is the next try.
- Whether the creep past 75 s should stop at 38 m/s or keep going.
- Whether the camera needs to rise less on a 3.5 m roof to keep the road in view. Answered in step 5: no, rising less made it worse; it rises the full height.
