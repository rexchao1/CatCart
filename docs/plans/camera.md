# Plan: a camera that sees past the cat

Goal: the cat never hides the road ahead. At the top of a jump, on a tall cat tree, and jumping off one, you can still see what is coming over the hill.

Asked by Rex on 2026-10-05: "you can't really see anything up ahead of him because he kind of blocks the screen and goes really high."

## Why she blocks the view today

The run camera sits 2.9 m up and 4.4 m behind her, tilted down only about 3 degrees (`cameraBase`, `cameraPitch` in `GameScene.swift`). It looks almost straight ahead at about her height.

- On the road, the cart and cat sit low on screen and the road runs up past them. Fine.
- In a jump she rises 2.6 m, but the camera only rises 0.09 m per meter (about 0.23 m). At the top, the cart is level with the camera, so it lands right on the horizon, which is where the far road is and where things come over the crest.
- The curved-world bend (drops 0.0011 x d² past 10 m) pulls the far road down into the same band of screen she covers, so the bend makes it worse.
- On a 3.5 m roof the camera rises the full height, so she sits where she does on the road. But it catches up at 4 per second, so for about half a second after she lands up there she sits high on screen. Jumping off a tall roof is the same as a jump from the road.

## How Subway Surfers handles it

1. The camera is high and looks down. The runner sits in the bottom third and the road runs up the screen past him to the horizon. Even at the top of a jump he stays below the far road.
2. The camera follows the ground, not the jump. It rises onto a train roof and mostly ignores the jump arc. Cat Cart already does this.
3. The camera aims at the road ahead, not at the runner, so the horizon stays at one height on screen while he moves below it.

## Rules

- Higher and steeper. Starting guess: about 3.6 m up, 5.5 m back, tilted down 14 to 18 degrees. `3d-world.md` started near here (3.5 m up, 6 m back, 20 degrees) and was tuned flatter later. Final numbers are Rex's pick from screenshots.
- The camera aims at a point on the road about 25 m ahead, at the height of the floor she rides (road, roof, or ramp). The tilt comes from that aim, not a fixed angle, so the horizon stays put when she climbs a tree.
- Measured goal: at the top of a jump, on the road and off a tall roof, the top of her head stays below the far road on screen (the road at about 40 m).
- The camera still ignores most of the jump arc. The 0.09 m per meter bob stays unless the screenshots say otherwise.
- Up fast, down slow: the camera rises onto a roof quicker than today (aim for about 0.2 s), and keeps the gentle ease coming down.
- Lane follow (60%), lane roll, speed FOV widening, crash shake, and the home screen swoop keep working as they do today.
- Her silhouette from behind: the PRD says the run view shows the back of her round head and shoulders over the box rim. A steeper camera sees more of the top of her head and the box. Check that it still reads as her.

## Things that could break

- The sky. The two sky pictures hang on the camera, centered on where it points. Tilting the camera down tilts them too, so the painted horizon may no longer meet the fog. Likely fix: hang them level and at horizon height, not on the camera's center line.
- The spray bottle peeks up from the bottom of the screen at 1.7 m behind the cart. With the camera further back and higher, it may sit somewhere else on screen.
- Lamps and anything overhead (the low things you duck under) could clip a higher camera. The middle lane has no lamps for this reason.
- More road on screen means more of the near road and less sky; check that the fog still hides things popping in at about 118 m.
- Shadows: `maximumShadowDistance` is 45 m. A steeper view shows more near road, so it should still cover it, but look.

## Done when

- At the top of a jump, on the road and off a tall roof, you can see the road over the crest above her head.
- Landing on a tall roof doesn't leave her high on screen.
- Rex has picked the framing from screenshots, and played it on the phone.
- Sky meets fog with no seam in all four worlds; the bottle, the home swoop, the crash shake, and the death panel still look right.
- `CATCART_PERF=1` shows no new hitches.
- The PRD's camera line describes the new camera.

## Steps

| # | Step | State |
|---|---|---|
| 1 | Baseline screenshots in the simulator: a plain run, the top of a jump on the road, riding a tall roof, just after landing on one, and the top of a jump off one. Use `CATCART_WAVE` with a tall-tree mix and the pilot or `CATCART_SWIPES` to hit those moments. Note where her head sits against the far road in each | todo |
| 2 | Aim the camera at a point down the road at her floor height, instead of a fixed tilt, with today's numbers. It should look the same on the road | todo |
| 3 | Fix the sky so it stays level when the camera tilts down | todo |
| 4 | Try three framings (today, a middle one, and the 3.6 m / 5.5 m / about 16 degree guess). Same five shots for each, side by side, for Rex to pick | todo |
| 5 | Up fast, down slow onto roofs | todo |
| 6 | Only if step 4's pick still covers the road at the top of a jump off a tall roof: lift the camera just enough to keep her head below the far road | todo |
| 7 | Check the fallout list: bottle, lamps, home swoop, crash shake, lane roll, death panel, all four worlds. Perf run. Update the PRD camera line | todo |
| 8 | Rex plays it on the phone | todo |

## Open questions

- How much of her face and back Rex wants to keep versus how much road he wants to see. Step 4 answers it.
