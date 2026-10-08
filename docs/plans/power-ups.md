# Plan: cat power-ups

Goal: make runs more fun the way Subway Surfers does, with power-ups to look forward to and use. Asked by Rex on 2026-10-08: "improve the game so it is way more fun to play like subway surfers, with some cat power ups."

## The four power-ups

Each is Subway Surfers' idea turned into a cat one. They show up on the road like a can of food, turning slowly inside a soft colored bubble, and work the moment she rolls into one.

| Power-up | Subway Surfers | What it does | How long |
|---|---|---|---|
| Fizz Rocket 🚀 | Jetpack | The four La Croix cans in her box fizz like rockets. She lifts to 4.8 m and flies over everything, steering through a winding trail of food in the sky. | 5 s, or long enough to pass everything already on the road (up to 9 s), then she lands once the road ahead is clear |
| Can Magnet 🧲 | Coin magnet | Food up to 26 m ahead, in every lane, flies to her. A red horseshoe magnet bobs over her shoulder. | 10 s |
| Pounce Springs 🐾 | Super sneakers | Springs under the wheels. Jumps peak at 4.4 m instead of 2.6 and hang a little longer, high enough to land on a tall cat tree from the road. | 10 s |
| Nine Lives 😇 | Hoverboard | A gold halo over her head. The next crash doesn't end the run: she loses the halo, whatever she hit is knocked away (or she bounds up onto the tree), and she blinks, safe, for 1.2 s. A second stumble while the bottle chases her counts as a crash, so the halo saves that too. | Until it saves her, or 20 s |

## Rules

- The first power-up comes about 9 s into a run, then one every 14 to 20 s. It takes the place of one can of food in a mix, so it's always somewhere food is: reachable, never in a blocked lane. Never one she already has, never the same one twice in a row.
- They stack. Grabbing one she has restarts its timer.
- Each one shows its name once in big type when she grabs it ("Fizz Rocket!"), with a haptic, and a round timer badge under the score pill that runs down. No sound (the PRD leaves sound undesigned).
- Flying: lane changes still work. Swipe up and down do nothing. Coyotes, low things, and trees pass under her, and road food is out of reach. The bottle gives up. The camera rises with her so she keeps her spot on screen; at 4.8 m it sits at about 8.8 m, under the 9.8 m line where ceiling beams start.
- A mix reaches as far as 50 m past where it appears, so 5 s of flight at an early speed doesn't pass everything on the road. At takeoff the flight is stretched to pass the farthest thing already there (up to 9 s), and the sky trail runs that far (up to 140 m). While she flies, no new mixes come for the first part of the flight; they start again so they reach her just after she lands. If something is still within 30 m of where she'd come down, she flies on up to 2.5 s more. After landing she can't crash for 1.2 s.
- The camera rises with 80% of her height while she flies, so she sits a little higher on screen than on the road, about where the top of a jump off a tall tree puts her.
- No score multiplier (Rex's call, 2026-10-04). No hoverboard (PRD "Not now"); Nine Lives is the cat's version of being saved once.

## Constraints

- PRD locks stay: cat, cart, coyotes, wet food, trees, four worlds at about 10 s, one thumb, no buttons in the run.
- Everything is built before the run (performance plan): two of each pickup in the pool, and the food pool grew from 28 to 60 for the sky trail (up to 28 cans).
- No screen-wide particle storms: a puff when she grabs one, bubbles under the box while flying.

## Done when

- Each power-up works in the simulator, seen in screenshots and in the `CATCART` log lines.
- Pickups show up on their own in a normal run.
- The PRD has the player-facing rules.

## Steps

| # | Step | State |
|---|---|---|
| 1 | `PowerUp` type, pickups in the pool, one placed in a mix in place of a food can | done |
| 2 | Fizz Rocket: flight, sky trail, mixes held back, clear landing, grace | done |
| 3 | Can Magnet: pull food from every lane | done |
| 4 | Pounce Springs: higher jump, springs on the cart | done |
| 5 | Nine Lives: save one crash, knock away what she hit | done |
| 6 | Callout and timer badges | done |
| 7 | Simulator check of each, PRD | done |

## Testing

- `CATCART_SWIPES="4:rocket"` (or `magnet`, `pounce`, `lives`) gives her that power-up at 4 s through the same code as a pickup. Lines print `power rocket`, `rocket landing`, `saved by nine lives`.
- `CATCART_POWEREVERY=4` puts a power-up in a mix every 4 s, the first at 4 s. `CATCART_POWER=rocket` makes them all that one.
- Nine Lives without god mode: `CATCART_SWIPES="3:lives,5:stumble,5.3:stumble"` is a catch by the bottle, which the halo saves.

## Checked

In the iPhone 17 simulator (iOS 26.5) on a GitHub macOS runner, 2026-10-08:

- It builds clean. Each power-up, given with `CATCART_SWIPES`, shows its callout, its timer badge, and its look: fizz bubbles and the sky trail, the horseshoe magnet, the springs, the halo.
- The rocket took off at 123 m and landed at 280 m on a clear road; food in the trail counted up.
- With Nine Lives, a catch by the bottle printed `saved by nine lives` and the run went on.
- Pickups show up in normal runs (every mix log after about 9 s has one now and then; `CATCART_POWEREVERY=4` shows them on the road).
- `swift scripts/check_game_art.swift` passes.

## Not checked

- A Pounce Springs jump at its peak, in a screenshot: that simulator takes about 3 s per screenshot, so the bursts never caught it. The springs and badge show, and the peak follows from the jump formula (`jumpPeak` 4.4 m).
- Frame rate on a real iPhone. The pickups are a few primitives each; a full sky trail is up to 28 food cans at once, while the road under her is emptying.
