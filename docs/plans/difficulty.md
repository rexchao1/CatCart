# Plan: a run that gets harder and stays fair

Goal: like Subway Surfers, a run starts gentle, speeds up, and throws harder obstacle mixes the longer you last, while staying playable at top speed.

Asked by Rex on 2026-10-03.

## What was wrong

- Speed rose in a straight line from 17 to 30 m/s and hit the cap at about 60 s. After that nothing got harder.
- Every obstacle mix was picked at random from the first second, so the hardest one could show up first and the game never escalated.
- Gaps between mixes were in meters. At 30 m/s a 20 m gap is 0.67 s, shorter than the 0.8 s jump, so a coyote could land under you.
- Cat trees were 11 to 17 m long at any speed, so at top speed a ride lasted under half a second.
- A swipe up a moment before landing was thrown away, which feels like a dropped input at speed.

## Constraints

- PRD locks: start at 17 m/s, top out at 30. Coyotes you jump, trees you ride, never block all three lanes without a jump or ride out. Mom's game: generous jump window.
- Keep it in `GameScene.swift`, teaching comments, no framework.

## Design

- One `ramp` from 0 to 1 over about three minutes, eased so it climbs fast early and settles. Speed, gaps, jump, and obstacle mix all read it.
- Obstacle mixes come in three tiers: easy from the start, medium from about 15 s, hard from about 45 s. Easy ones fade out as the ramp rises.
- Every distance inside a mix is written at 17 m/s and stretched with speed, so the timing of a mix feels the same at any speed. Gaps between mixes are in seconds and shrink from 1.75 s to 1.05 s.
- Rule that keeps it fair: every lane of every mix can be survived by staying in it and jumping. Same-lane hazards are at least about 1.1 s apart. The test pilot, which only jumps and never steers, should survive at top speed.
- The jump keeps its 1.9 m peak but gets quicker as speed rises (0.8 s to about 0.66 s), so it does not sail over half the screen.
- Cat trees stretch with speed so a ride lasts about the same time.
- A swipe up up to 0.18 s before landing is remembered and fires on touchdown.
- `CATCART_TIME=<seconds>` starts a run that far into the difficulty ramp, for testing.

## Done when

- Early run reads easy; mixes get denser and harder over the first minute or two.
- Pilot without god mode survives 60+ s starting at `CATCART_TIME=200`.
- PRD describes the new rules.

## Steps

| # | Step | State |
|---|---|---|
| 1 | Ramp, speed curve, jump that tightens with speed, jump buffer | done |
| 2 | Tiered mixes, scaled offsets and tree lengths, gaps in seconds | done |
| 3 | `CATCART_TIME` switch, build, pilot survival check at top speed | done |
| 4 | PRD update | done |

Result 2026-10-03: pilot with crashes on survived 90 s from the start (909 m at 45 s) and 90 s at top speed from `CATCART_TIME=200` (2725 m). Not yet played by hand.
