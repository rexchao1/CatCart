# Plan: a camera that sees past the cat

Goal: the cat never hides the road ahead. At the top of a jump, on a tall cat tree, and jumping off one, you can still see what is coming over the hill.

Asked by Rex on 2026-10-05: "you can't really see anything up ahead of him because he kind of blocks the screen and goes really high."

## Why she blocked the view

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

- Higher and steeper, from the same distance back: 4.0 m over the floor she rides (was 2.9), 4.4 m behind her (same), tilted down about 14 degrees (was 3) by aiming at the road 12 m ahead of her. Field of view 50 degrees across (was 56), so she stays the size she was. On the road she sits where she did, about two thirds down the screen; the crest moved up from the middle to about 43% down.
- The camera rides the floor she's on (road, roof, or ramp) all the way up, and 60% of a jump. The old camera rose three quarters of the way onto a short roof and 0.09 m per meter of jump.
- Up fast, down slow: it eases toward its goal at 12 per second going up and 5 coming down (was 4 both ways), so landing on a tall roof doesn't leave her over the crest.
- The sky pictures hang on a pivot under the camera that tilts them back up to the old 3 degree angle, so the painted horizon still meets the fog. The tilt fades out on the swoop to the home screen, whose camera already holds the sky right.
- Nothing hangs over the road below 9.8 m (`overheadClear` in `Scenery.swift`). The camera tops out near 9.1 m at the top of a jump off a tall tree, and she reaches 7.7 m. Before this, the city bunting dipped to 5.5 m, the jungle moss to about 5 m, and the house beams sat at 7.1 m, so she and the camera already went through them on tall trees.
- Lane follow (60%), lane roll, speed FOV widening, crash shake, and the home screen swoop work as before.

## How the numbers were picked

A small model (screen height of the crest and of her, from camera height, distance, tilt, jump follow, and field of view; it matched the screenshots) compared framings. The bind: the camera's height over her at the top of a jump decides whether she covers the crest. Pulling the camera back for a gentler angle shrinks her; following more of the jump makes the world bob. 4.0 / 4.4 / 12 / 0.6 / 50 keeps her the old size and spot on the road and leaves a clear gap under the crest at the top of a jump (about 9% of the screen). The first try, 4 m up and 6 m back at 56 degrees, cleared the crest by only about 3% and made her a third smaller.

Checked in shots, by number (fraction of screen height, from the top): before, the top of a jump put her at 0.37 to 0.50 with the crest at 0.52, right over it. Now she's at 0.53 to 0.66 with the crest at 0.44.

## Checking it

`scripts/camera_shots.sh [out dir] [world]` takes the six moments as frozen frames and lays them side by side. `CAM="4,4.4,12,0.6,50"` tries other numbers without a code change (the `CATCART_CAM` test hook). Freezes come from a `freeze` step in `CATCART_SWIPES`.

## Done when

- At the top of a jump, on the road and off a tall roof, you can see the road over the crest above her head.
- Landing on a tall roof doesn't leave her high on screen.
- Sky meets fog with no seam in all four worlds; the bottle, the home swoop, the crash shake, and the death panel still look right.
- `CATCART_PERF=1` shows no new hitches.
- The PRD's camera line describes the new camera.
- Rex plays it on the phone.

## Steps

| # | Step | State |
|---|---|---|
| 1 | Baseline screenshots of the six moments | done |
| 2 | Camera aims down the road at a set tilt, rides the floor plus part of the jump, up fast and down slow | done |
| 3 | Sky held at the old angle when the camera tilts down | done |
| 4 | Compare framings (model plus shots) and pick one. Rex left the pick to the agent | done |
| 5 | Up fast, down slow onto roofs | done (in step 2) |
| 6 | Extra lift at the top of a jump off a tall roof | not needed: step 4's pick already clears the crest there |
| 7 | Fallout: overhead things raised to 9.8 m; bottle, home, swoop, death panel, all four worlds checked; perf run; PRD camera lines | done |
| 8 | Rex plays it on the phone | todo |

Result (2026-10-05, iPhone 17 Pro simulator): the six moments in city, and riding and jumping off a tall tree in jungle, house, and farm, all show the road and the crest above her. The spray bottle now shows in full, hopping beside the cart, where it used to peek up from the bottom edge. The death panel is unchanged. The house hall is taller (walls 10 m, was 7.2), and the bunting and the jungle branch hang higher, framing the top of the view. `scripts/perf_run.sh 45 house`: steady 16.7 ms frames; the two hitches at run start were there before. Not played by hand yet.

## Open questions

- From 4 m up she's seen from a bit higher (about 35 degrees down at her, was 24), so more of the top of her head and the cans in the box show. Rex to judge on the phone whether she still reads as her from behind.
