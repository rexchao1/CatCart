# Cat Cart PRD

Read this before changing look, feel, art, or mechanics. If a request fights this file, ask. Do not silently overwrite a locked call.

Owner: Rex. Player: his mom. The game is a gift, not a store product yet.

Working title: Cat Cart. Bundle: `com.rexchao.catcart`. iPhone only, portrait, one SwiftUI window. The world is real 3D in SceneKit. The kitten, her La Croix cart, coyotes, and wet-food cans are 3D models. The HUD is a SpriteKit layer on top.

---

## The game

A portrait 3-lane endless runner, like Subway Surfers seen from behind the character.

You are a round-faced lilac British Shorthair kitten, about six months old, sitting in a custom-fit La Croix 12-pack box with wheels. You roll down a path that keeps changing worlds. Coyotes come at you. Jump them. Low things hang across a lane. Duck into the box to pass under. Cat trees sit in a lane like trains. Jump on and ride the top. Some lanes are blocked outright, a coyote prowling under a low thing, so you have to steer. Clip something and you stumble, and a green spray bottle chases you. Grab cans of wet food. Run as long as you can for the highest score. Best score is saved on the phone.

It should feel easy to pick up in an ad, then a real challenge once you are playing: like Subway Surfers, a good run is something to brag about. One thumb. Swipe. No menus to learn before the first run.

---

## Who it is for

Mom, on an iPhone, in portrait, probably on the couch. Big readable objects. A short gentle start (about 8 seconds), then it gets hard for everyone, mom included; there is no easy mode (Rex's call, 2026-10-04). A crash should feel silly, not punishing. The cat is cute. The coyotes are mean on purpose, so the cute/danger contrast is the joke.

Rex is learning while we build. Teaching comments in the Swift files stay. Do not turn this into an engine or a framework.

---

## Locked look

These came from Rex. Treat them as the product, not sketches.

### The cat

Lilac British Shorthair kitten, about 6 months, modeled on Rex's real cat. Natural proportions: round head with full cheeks, small cupped ears, golden eyes, a sturdy seated body with distinct front legs (Rex's call, 2026-10-03, replacing the oversized cartoon head). Coat is warm dove gray with only a faint dusty-lilac cast. Not purple. Not a Russian Blue. Camera is behind her for the run, so the silhouette is the back of her round head and shoulders over the box rim.

She is cute and real, not a smooth toy (Rex's call, 2026-10-08: "it looks like a marshmallow"). She has soft fur with a fuzzy outline that lies the way cat fur lies, round golden eyes with catchlights (not oversized: Rex's call, 2026-10-08, "make its eyes smaller"), a lilac-pink nose, round cheeks and whisker pads, a paler muzzle and chest, and small round-tipped ears. Her orange collar is snug, up under her jaw where her neck is narrowest (Rex's call, 2026-10-08, "make its collar tighter"). On the home screen she tilts her head at you and sometimes gives a slow cat blink.

Default pose is sitting in the box. Laying-down takes exist so Rex can compare. Do not switch the in-game pose until he says which one stays.

### The cart

A real La Croix sparkling-water 12-pack: the short, flat cardboard case, icy baby-blue wrap, navy script on the back. It is a custom box that fits him. He sits in it. Wheels on the four corners. Small wheels and big wheels were both generated so Rex can pick.

The box says LaCroix in navy brush script with "SPARKLING WATER" under it, on an icy-blue wrap with waves and fizz (Rex's call, 2026-09-30: the real name, not Sparkle Wave). The lettering is set in type by `scripts/make_cart_textures.py`, never by an image generator. Four cans stand in the corners. The real brand name is fine for a family gift; it would have to change before any App Store release.

In the game the cart is 3D (`CatCart/KittenCart.swift`): cardboard walls, the logo on the back and front, four spinning wheels. The kitten's source is `art/models/kitten/cat.blend`, built by `scripts/blender/make_kitten_v3.py` (revision 4, 2026-10-08; the study and its renders are in `art/options/kitten-cute-v3b`, and the first take with bigger eyes and a looser collar in `art/options/kitten-cute-v3`). `scripts/build_kitten.sh` turns it into the game model: `scripts/blender/export_kitten.py` drops the studio and the strand fur, cuts her to about 24k triangles in the parts the game animates, darkens the creases, and writes JSON; `scripts/build_kitten.swift` adds the in-game colors, the painted iris, and the shell fur, and writes `cat_kitten.scn`. Edit the study script or the .blend, then rerun it. The previous kitten (revision 2, no fur) is `art/options/player/kitten-v2.scn`, and the old cartoon kitten is `art/options/player/kitten-cartoon.scn`, built by `scripts/blender/make_cat.py`. Her tail is held up so the name on the back stays readable. The photos themselves are never committed or uploaded.

### Obstacles and pickups

Coyotes replace crates and flower pots. They look dangerous: lean, ragged, bared teeth, amber eyes. Their faces move (snarl cycle). You jump over them. You do not land on them.

Pots are gone. Do not bring them back unless Rex asks.

Low things are the duck obstacles (Rex's call, 2026-10-04). One per world, each built in code in `makeLowThing` in `GameScene.swift`: a striped construction scaffold in the city (steel frames with X braces, a walk board, a rail, a paint bucket, and amber lamps that blink), a mossy log on two stumps in the jungle (vines round the stumps, roots, mushrooms and a fern on top), a table with a red gingham cloth in the house (turned legs, a cloth that drapes all round with folds, two plates, a fish, a mug, a vase of flowers), a clothesline on the farm (a blue sheet and a yellow towel that sway on the line, a red sock, pegs, a bird on the post, grass at the feet). Each fills one lane, has open space under it down to the road, a shadow strip on the road, and its bottom edge at 1.38 m, between her ducked head (about 1.25 m) and her sitting head (about 1.68 m). Only the posts at the lane edges reach below that edge; the rest of each one stays under 2.0 m, where a jump clears it. Coyotes stay jump-only; there is no leaping coyote.

A blocked lane is a coyote prowling under a low thing (the coyote is 1.14 m tall, so it fits). Jump and you hit the low thing; duck and you hit the coyote. The only way past is to steer. This is the Subway Surfers wall, built from pieces the game already has (Rex's call, 2026-10-04).

The chaser is a green plastic spray bottle with a white trigger head, built in code in `buildBottle` in `GameScene.swift`. It hops along just behind the cart, to her right and turned side-on so the trigger and nozzle show, and leans over her to spray when it catches her.

Yarn is gone. Collectibles are small cans of wet cat food, big enough to read as food. Some hang in the air over a coyote, at jump height (2.0 m), with no shadow; only a jump reaches them. The current can has a turquoise wrap, white salmon symbol, open silver lid, and visible salmon in gravy. The turquoise distinguishes it from the tan and brown coyotes.

The food source is `art/models/food/wet-food.blend`; the coyote source is `art/models/coyote/coyote.blend`. Run `scripts/build_art.sh` after editing them. It exports lightweight meshes into `wet_food.scn` and `coyote_run.scn`, embeds the food label, and gives the coyote a gallop and snapping jaw. The render-only fur and studio stay out of the game. `swift scripts/check_game_art.swift` checks the exports and renders previews. The old coyote is saved in `art/options/coyote/coyote-original.scn`.

### Cat trees

These are the Subway Surfers trains. A cat tree occupies one lane, with a flat carpeted top the cart can roll on. Sisal posts, cubbies, hanging toys are fine as long as the rideable roof is obvious.

They look like real, high-end cat furniture, creative and fun (Rex's call, 2026-10-09: "The trees have to look like real cat trees that also are creative and realistic and fun"). The roof is a thick cream carpet platform with rounded edges and a trail of paw prints pressed into the pile, flat for its whole length with nothing standing on it. Under it, thick sisal-wrapped posts (visible rope wraps) frame bays that hold carpeted condos with round portholes in a rolled cream rim or arched doorways, and cat ears on top of the porthole condos. Open bays take turns holding a hammock slung between the posts, a carpet tunnel on the floor (a lookout tube on a tall tree's upper story), or a sisal scratch board leaning up the outer side with cream steps. Toys swing on strings under the roof's edge, outside the ride: a pom-pom at the front, a toy mouse or a feather at the back. Each tree picks an accent carpet (cream, soft gray, mint, blush pink, lavender, or sand) and a toy color, so trees on the road differ. Big readable shapes first: everything has to read from the run camera through the fog. Nothing stands above the roof in the ride path, nothing sticks out of the lane or in front of the tree's front edge.

Two heights and a ramp (Rex's call, 2026-10-05):

- Short tree: one story of cubbies, roof at 2.0 m (was 1.5). A jump from the ground lands on it.
- Tall tree: two stories of cubbies on a carpeted shelf, roof at 3.5 m. A jump from the ground can't reach it, so its front is a wall. You get up by a ramp or by jumping from a short tree's roof. It is the one tree that should read as a tower you smash into from the road, with its flat roof still obvious.
- Ramp: a carpeted slope with sisal rope along its edges, a sisal scratch-pad runner up the middle with cream steps across it, and the roof's paw prints leading up, climbing from the road to the front of a tree. It is 8 m long at the start speed and stretches with speed like a tree, so the climb takes about half a second. The slope is the gameplay; the steps are 5 cm of trim.

This is the hard piece. The sprite, the lane width, and the ride length have to agree. If the tree looks like a tall tower you smash into, or like a rug with no height, it is wrong.

### Worlds

The run travels through four places, in this order, looping:

1. Streets of a big city
2. Jungle
3. Inside a house
4. Farm

Each world lasts about 10 seconds. You drive into the next one: the road ahead turns into the next place, and the sky, fog, and light blend over as the border comes at you, finishing as the cat crosses it. Nothing fades or cuts on the whole screen at once (Rex's call, 2026-09-30, replacing the old crossfade).

The worlds are built from 3D model kits (free CC0 kits, listed in `art/models/SOURCES.txt`), in one bright, chunky cartoon style like Subway Surfers. The road is a flat textured strip per world, drawn by `scripts/make_3d_textures.py` (2026-10-09, Rex: "the road and background have to look better"): warm asphalt with cream lane dashes, a yellow curb line, tar patches and a manhole in the city; a packed dirt path with stones, roots, leaf litter, and mossy edges in the jungle; varnished floorboards under one wide runner rug whose woven stripes mark the lanes in the house; a sunny dirt track with tire ruts, gravel, and grass strips with wildflowers on the farm. Lane marks stay on the lane lines. The sky is a painted picture per world whose bottom half is exactly the fog color, so the far road melts into it; above that sits a hazy far layer (city skyline, jungle mountains and canopy, the lit end of the hall, rolling hills with a barn and windmill), then a sun glow and soft clouds. Each world also has its own light: a warm sun and a tinted ambient (blue shade in the city, green bounce in the jungle, cream indoors, sky blue on the farm), with a soft bloom, a touch more saturation, and a faint vignette on the camera. The roadsides carry small life: mailboxes, bus stops, trash cans and cones in the city; ferns, lianas, flowers, rocks, and ponds in the jungle; cat beds, bowls, scratching posts, toys, clocks, and book shelves in the house; sunflowers, troughs, scarecrows, haystacks, and hens on the farm. The first roads and skies are in `art/options/roads-v1` and `art/options/skies-v1`.

### UI

Casual, creamy, icy-blue, paw ornaments. HUD is two pills: score, food count. While she has a power-up, a round cream badge with its picture sits under the score pill, its gold ring running down as it wears off; grabbing one shows its name once in big type ("Fizz Rocket!"). The home screen looks at her face from the front: big white "Cat Cart" title in chunky rounded type with a navy outline, a one-line hint, a glossy "Tap to play" button with the paw on its end, and the best score. Tapping swoops the camera around behind her and the run starts. Death dims the world and pops a rounded panel: a pink "Oh no!" ribbon, three big numbers across (score, food, and time survived like 1:12), the best score under them, and a gold "New best!" sticker when she beats it. No other stats. A "Dash again" paw button pops in under it once the 1 s death pause is over, and a tap then runs again without going home (Rex's call, 2026-10-05). The pills hide while the panel is up. No tiny type. No clutter. Extra panel and button takes live in `art/options/ui` for Rex to delete.

---

## Locked feel

Copy Subway Surfers where it matters. Invent around the cat, not around the camera.

### Camera and speed

Behind the cat and above her, looking down the road like Subway Surfers, three lanes. The road bends down over a hill in the distance ("curved world", a shader on every 3D thing), and fades into fog, like Subway Surfers. Objects come over the crest small, grow, and rip past the camera. They must not slow down at the cat or behind him.

The cat never moves forward. The whole track (road, scenery, coyotes, food, trees) slides toward the camera at one speed. If a cobble and a coyote at the cat's feet leave the screen at different times, the motion is broken.

Do not cap motion in screen pixels. Tune with `runSpeed()` in meters per second: 17 m/s at the start, rising to 34 at 75 s (Rex's call, 2026-10-05, was two and a half minutes). It climbs fast early and settles (about 20 at 8 s, 25 at 20 s, 28 at 30 s, 31 at 45 s), so it's hard by 30 s. After 75 s speed keeps creeping up 1 m/s every 30 s and stops at 38 (about 3:15), so long runs still get harder; the jump, clear height, and gaps stay where they are at 75 s. Things appear about 118 m ahead, inside the fog.

The camera trails the cat: it follows her lane partway, rises with the floor she rides (road, roof, ramp) and with a little over half of each jump, rolls a touch on lane changes, and widens a little as the run speeds up. She never hides the road ahead: on the road she sits about two thirds down the screen, and at the top of any jump, from the road or off a tall tree, she stays under the crest where things come into view (Rex's call, 2026-10-05). Anything hanging over the road (bunting, branches, ceiling beams) stays above 9.8 m so the camera never passes through it.

### Lanes

Three readable tracks at the cat. Tight at the horizon. The cart fits in one lane and does not spill into neighbors. Swipe left or right to change lane. A little tilt on the cart is enough.

### Jump

Swipe up to jump. The jump is a real arc: up to 2.6 m (4.4 m with Pounce Springs) and back down under gravity (Rex's call 2026-10-05, was 1.9 m: "I just want the animation higher"). How long she stays in the air is not locked; tune it freely (`jumpAirtime` in `GameScene.swift`, Rex's call 2026-10-03). Today it is 0.68 s at the start and quickens to about 0.59 s at full ramp (75 s) (Rex's call, 2026-10-05: stronger gravity, faster takeoff and a faster drop; was 0.9 to 0.78 s). The higher peak kept the same airtime, so she just leaves the ground faster and falls harder; every timing stayed the same. Keep the obstacle spacing longer than a jump plus a moment to react (see Getting harder). A swipe up just before she lands (under 0.2 s) is remembered and she jumps the moment she touches down. Swipe down mid-air to drop fast. Jumping onto a cat tree keeps the arc going, so she comes down on the roof at the end of it, not the instant she reaches the tree. If she catches the roof low, she hops up onto it. (Rex's call, 2026-09-30: the old 1.15 s held hang stayed in the air too long and snapped down onto trees.)

She has a jump pose (Rex's call, 2026-10-08, asking for more realistic, cuter animation): she stretches tall and looks up as she rises, tucks and curls forward as she falls, ears back and tail streaming against the motion, and the box dips on its wheels when she lands. It is all springs driven by her vertical speed (`KittenCart.swift`), so a slam, a step down off a tree, and a full jump each look different. None of it changes the arc or the timings.

Jumping is how you clear coyotes. Jumping onto a cat tree is how you ride.

### Duck

Swipe down on the ground and she ducks into the box for 0.45 s: her body squashes down inside the box, so only her ears, the top of her head, and her tail tip show over the rim. Then she pops back up with a little springy overshoot. Swipe down again while ducked to keep ducking. Swipe down in the air only brings her down fast; it never ducks (Rex's call, 2026-10-04: the 0.8 s duck lasted too long and the air swipe should just land). Swipe up while ducked and she pops straight into a jump. Lane changes keep the duck going. Ducking works on a tree roof too, but low things only stand on the ground lanes.

A low thing in her lane crashes her unless she is ducked near the ground or her jump carries her above 2.0 m (`lowTop`), about the middle half of the airtime (Rex's call, 2026-10-05: jump over them too). A late or early jump into one is a crash. A blocked lane (coyote under a low thing) can now also be cleared by a good jump. Ducking does not help against coyotes or a tree front.

Until she has ducked under her first low thing, ever, a bobbing "Swipe down to duck!" line shows below the cart as one comes (about 2 s out). It retires for good after the first success (`duckedUnderOnce` in UserDefaults).

### Cat trees, like trains

- A tree fills one lane for a stretch of depth.
- Hit the front at ground height: crash.
- Jump as the front arrives: land on the roof and stay up without holding jump.
- Ride until the back of the tree passes, then drop to the ground, or onto the next tree if one is right behind at the same height or lower.
- Swipe to a neighbor lane that also has a tree as high or lower: stay up, or drop onto it.
- Swipe to a lane with no tree: fall. If a coyote is there, crash.
- Swipe into the side of a tree from the ground, or of a tall tree from a short roof: bump off it, stay in your lane, and stumble. A jump high enough gets you on instead.
- Jump from a tree to hop to another tree or to clear something.
- A tall tree's front is a crash from the ground, even in a jump. From a short roof, a jump reaches it, and so does a Pounce Springs jump from the road.
- Roll onto a ramp in its lane and ride up onto the roof with no jump. Jumping on a ramp works too. From the side, you can steer onto a ramp where it is still low (under 0.5 m); higher up the side is a bump and a stumble.

Never block all three lanes with no jump, duck, or ride out. A tall tree with no ramp and no short tree right before it in its lane counts as a blocked lane. Two trees plus a food lane is fine. Three coyotes is a forced jump, and three low things a forced duck, both used rarely. Two blocked lanes with the third open is fine; that's a forced steer.

### Getting harder

Like Subway Surfers: easy to start, hard the longer you last, and endless. Rex's calls of 2026-10-04 are in `docs/plans/challenge.md`.

- One difficulty ramp drives speed, the jump, the gaps, and how much the mixes lean hard. It's full at 75 s (see Camera and speed).
- The road is already filled when the run starts, so the first coyote reaches her about two seconds after the tap (Rex's call, 2026-10-05, was about eight).
- Every mix has at least two or three obstacles; there are no food-only mixes.
- The first 8 s are easy mixes only: two or three coyotes one move at a time, a tree with coyotes beside it, food over a coyote, two short trees side by side, a ramp onto a short tree, a gate of two trees with a coyote between. Medium mixes (two busy lanes, slaloms and snakes, coyote then tree, double hops, low things to duck, the first blocked lanes) join at 8 s, and so do tall trees and ramps: a ramp up a tall tree, a staircase up (short tree, then tall), a step down from a tall roof to a short one, twin trees of different lengths, a long pair with food zigzagging between the roofs, a pair that walks across the road, and a ramp beside a tall wall. Hard mixes (back-to-back coyotes, tree hops, a staircase of trees, jump then duck then jump, lanes that flip, both sides blocked, a blocked zigzag, a gate of blocked lanes with a tree to ride through, a blocked lane that walks across the road, the rare three-coyote and three-low-thing walls) join at 20 s, with the hardest tree mixes: a tree yard of three staggered trees to hop across, a wall of tall trees with a ramp up the middle, a gap jump, a pick-your-way-up row (staircase, wall, ramp), and two long trees with coyotes between them.
- Cat trees are in about half of all mixes at any point in a run (Rex's call, 2026-10-05, was about 30%): each tier is about half tree mixes by weight. These two times are fixed in seconds (Rex's calls of 2026-10-05: medium was 15, hard was 40 and then 25). Easy mixes thin out by about 30 s but never vanish; they keep 15% of their weight.
- Distances inside a mix grow with the square root of speed, so a faster run leaves less time between things: two coyotes in a lane are 1.1 s apart at the start, about 0.8 s at 34 m/s, and 0.75 s at 38.
- The gap between mixes is 0.9 s at the start and shrinks to 0.25 s at 75 s (0.45 s at 30 s), so mixes run into each other.
- Fairness rule: there is always a way through, and time to steer to it. Some lanes cannot be survived by staying in them, so steering is required, not just easier. Two things in one lane are at least 19 m apart (written at 17 m/s), and a low thing after a coyote 24 m, inside a mix and where one mix meets the next. Low things never stand beside the middle of a tree or beside a ramp, where a rider stepping off would drop into one. The gap jump is the one exception to 19 m: two short trees in a lane with an 8 m gap and a coyote in it, cleared in one jump from the first roof (about 0.4 s to take off), with a neighbor tree to step around on. New mixes are checked against this by hand.
- Cat trees stretch fully with speed, so a ride lasts about the same time; what comes after a tree moves back to match.

### Coyotes

Jump over. If you are high enough, or already on a tree, they pass under. High enough is 1.1 m at the start and 1.37 m at full ramp (75 s), so the useful part of a jump narrows as the run goes on (was 0.8 and 1.0 with the 1.9 m jump, scaled with it so it plays the same). A coyote has a body 1.5 m long, and you have to stay clear the whole time it's beside you. If you are on the ground in their lane when they reach you, crash.

### Crash or stumble

- Running straight into a coyote, a low thing, or a tree front in your lane is a crash.
- A glancing hit is a stumble: bumping the side of a cat tree, or clipping something mid-lane-change, in the lane you're leaving or the one you haven't reached yet. A lane change counts as done once the cart crosses the line between lanes. Clipping the lane ahead bounces you back.
- A stumble wobbles the cart, and the green spray bottle hops along right behind her for 4 s, then falls back.
- A second stumble while the bottle is there: it catches her and sprays her. That's a crash, with the usual panel.
- With Nine Lives, one crash or catch is saved instead (see Power-ups).

### Food

Touch to collect, even in the air or on a tree. Food hanging in the air sits at 2.0 m and needs a jump (above 1.23 m) or a tree roof to reach. Food on a roof or a ramp sits on the carpet. +1 food, +25 score, a pop. Food after a coyote in the same lane, or over one, is a reward for jumping, and food on the open side of a blocked lane rewards steering.

### Power-ups

Like Subway Surfers' jetpack, coin magnet, super sneakers, and the board that saves you, but cat ones (Rex's call, 2026-10-08: "way more fun to play like Subway Surfers, with some cat power ups"). One shows up on the road about 9 s into a run, then one every 14 to 20 s, in place of a can of food, so it's always somewhere she can reach. It turns slowly inside a soft colored bubble. Roll into it (or jump to it, if it hangs in the air) and it works at once. They stack; grabbing one she already has restarts it.

- Fizz Rocket (🚀, 5 to 9 s): the La Croix cans in her box fizz like rockets and she flies at 4.8 m, over coyotes, low things, and trees, through a winding trail of food in the sky. Swipe left and right to steer; swipe up and down do nothing up there, and road food is out of reach. The bottle gives up. She flies long enough to pass everything already on the road (5 s, longer when the road is busy), no new mixes come for the first part of the flight, and she only comes down once the road ahead is clear. For 1.2 s after landing nothing can crash her.
- Can Magnet (🧲, 10 s): food up to 26 m ahead, in every lane and in the air, flies to her. A red horseshoe magnet bobs over her shoulder.
- Pounce Springs (🐾, 10 s): springs under the wheels, and jumps peak at 4.4 m instead of 2.6, high enough to land on a tall tree's roof from the road. The springs squeeze flat when she ducks, so ducking still works.
- Nine Lives (😇, until used or 20 s): a gold halo over her head. The next crash, or a catch by the spray bottle, doesn't end the run: she loses the halo, "Saved!" pops up, whatever she hit is knocked away (a tree front, she bounds up onto it), and she blinks, safe, for 1.2 s.

No power-up changes the score, and there is still no multiplier or hoverboard.

### Score

A point per meter, plus 25 per can. No multiplier (Rex's call, 2026-10-04). The score counts up in the left pill during the run.

### Crash and retry

White flash, shake, haptic, and the cat tips over in her box. "Oh no!" with score, food, time survived, and best. For 1 s after the crash taps do nothing, so mashing the screen can't start a run by accident; the panel shows at once so you can read your numbers. When the pause ends the "Dash again" button pops in. Only a fresh tap restarts: a touch that starts after the pause and lifts without swiping. A swipe that was under way when she crashed, or any swipe on the panel, does nothing (Rex's call, 2026-10-05). Best score lives in UserDefaults as `bestScore`. The older best distances (`bestMeters`, `bestMeters3D`) are not carried over.

### Feedback that stays

Lane-change haptic and a scuff of dust off the wheels. Jump haptic and a small widening of the view as she leaves the ground. On landing: a puff, a ring that spreads on the floor and slides back with the road, a squash, and a camera kick, all scaled by how hard she came down (a slam or a Pounce Springs landing also gives a short, small shake). Dust from the wheels, tinted to each world's ground. A grabbed can hops up, spins once, and shrinks into her lap with a few sparkles; power-ups do the same, with a colored puff and a strong haptic, and bubbles from the box while the rocket flies. Food cans bob, turn slowly, and glint now and then; power-up bubbles have a soap-bubble rim. The spray bottle squashes and stretches as it hops and goes "psst" at the top of each hop, with a long spray when it catches her. A crash puts four cartoon stars circling over her head. The food pill pulses when you grab food; the score pill pops once each thousand points. Light speed lines at the screen edges. Every object has a soft shadow. Do not add score-pop spam or screen-wide particle storms. Mom's game, not an arcade cabinet.

---

## Controls

| Input | In a run |
|---|---|
| Swipe left / right | Change lane |
| Swipe up | Jump |
| Swipe down | On the ground, duck into the box. In the air, land now |
| Tap on the home screen, or on the death panel once "Dash again" shows | Start a run |

One finger. No on-screen buttons during the run. No tilt steering.

---

## Art process

Rex wants many takes, then he deletes. New look work follows that.

1. Generate options.
2. Put every take in `art/options/`, named clearly. Update `art/options/CHOICES.txt`.
3. Copy one default into `CatCart/Assets.xcassets` so the game runs.
4. Stop. Let Rex delete. Do not keep regenerating over his picks.

Defaults in the game today:

| Slot | File |
|---|---|
| Player | 3D kitten with shell fur from `art/models/kitten/cat.blend` (`cat_kitten.scn`) in the 3D La Croix cart |
| Coyote | 3D galloping coyote (`coyote_run.scn`), flat snarl pictures as fallback |
| Food | 3D turquoise salmon can (`wet_food.scn`) |
| Cat tree | condo tree with a flat paw-print roof, sisal posts, hammocks, tunnels, swinging toys, short (one story) and tall (two), carpeted ramp with a sisal runner |
| Worlds | 3D kits in `CatCart/Models`, roads and skies from `scripts/make_3d_textures.py` |
| UI | paw panel, paw button, hud bar |
| App icon | farm-road (kitten in cart, blue sky), from `scripts/make_icon.py` |

If he drops a different PNG onto the matching imageset, that is the new default. Honor it.

Sprites are isolated on transparency, no baked ground shadow. The game draws the shadow. World scenery is 3D models in `CatCart/Models`, built into segments by `Scenery.swift`. Road, sky, carpet, and effect textures come from `scripts/make_3d_textures.py`. The old 2D world paintings, walls, ground tiles, and side props are no longer used in the game.

---

## What is in the build now

This is the live game, not a wish list.

- SceneKit 3D world, portrait, iPhone 17 simulator scheme. SpriteKit HUD on top.
- Curved-world road with fog into a painted sky. Three lanes, arc jump and slam.
- 3D kitten with real-time fur in a 3D La Croix cart: wheels spin, tail sways, ears flick, eyes blink, head leans into turns. On the home screen she tilts her head at you, breathes, glances off to a side with an ear turned that way, and gives slow blinks.
- She moves like a cat, not a statue in a box (Rex's call, 2026-10-08: "a lot more realistic, more cute"). Everything is little damped springs in `KittenCart.swift`, driven by what the run is doing, not canned clips. Jump: the box rocks back on its wheels, she squeezes then stretches tall on the way up, ears pin back, head tips up to look ahead at the peak, tail lags down; falling, she tucks and curls forward and the tail streams up. Landing: the box dips on its suspension, she squashes, her head nods and bobs a beat late, ears flop, tail whips. Lane change: her head looks where she is going, she and the box lean in, the box yaws and settles, the tail counter-swings with the tip trailing like a whip. Riding: a faint road rattle, breathing, uneven tail sway, asymmetric ear flicks that sometimes answer each other. Duck: ears fold flat and pop back up with her. Fizz Rocket: ears blown back and fluttering, tail streaming out behind. Crash: ears back, eyes squeezed shut, tail down, on top of the tip-over. The duck heights in `docs/plans/duck.md` still hold: the stretch is off while she is ducked.
- The cart has toy-wagon tires (fat rounded rubber, pale hub, chrome center cap) and the hand holes a real 12-pack has cut near the top of each end.
- Four power-ups on the road: Fizz Rocket (fly through a food trail), Can Magnet, Pounce Springs (high jumps), Nine Lives (one saved crash), with a callout and timer badges.
- 3D coyotes with a looping gallop and snapping jaw. Jumpable.
- 3D turquoise wet-food cans, single cans and lines of cans, some sitting on tree roofs.
- Cat trees as real 3D cat furniture: paw-print carpet roof, sisal posts, condos with portholes and cat ears, hammocks, tunnels, scratch boards, swinging toys, an accent carpet per tree. Short trees (2.0 m roof) and tall ones (3.5 m, two stories), some with a carpeted ramp to roll up. Ride, hop to a neighbor tree, step down from a tall roof, jump a gap from roof to roof, fall off the end, bump off the side. Trees are in about half the mixes, from the first seconds; tall trees and ramps from 8 s.
- Duck into the box with a swipe down. One low thing per world to duck under, from 8 s. A one-time hint teaches it (not shown for a blocked lane).
- Speed from 17 to 34 m/s over 75 s, then a slow creep to 38. Blocked lanes (a coyote under a low thing) from 8 s, so steering is required. Hard mixes from 20 s. The road starts full, mixes have two or more obstacles, and the gap between them shrinks to 0.25 s.
- Stumbles on glancing hits, a green spray bottle that chases for 4 s, and a second stumble gets her caught.
- A score (meters plus 25 per can), shown during the run, on the death panel, and as the best.
- Four worlds built from 3D kits, about 10 s each. You drive into the next one while sky, fog, and light blend.
- Soft shadows, world-tinted wheel dust, landing squash and ring, camera kicks and shakes, collect pop with sparkles, crash stars, trailing camera, speed lines.
- Home screen facing her, swoop into the run. HUD pills. Death panel with score, food, and time, a 1 s pause before "Dash again" shows, and a restart only on a fresh tap.
- Art options sitting in `art/options` for Rex to prune.

Known gaps against this PRD:

- Coyotes gallop in step with each other.
- No sound.

---

## Not now

Do not add these unless Rex asks.

- Other characters, hoverboards, missions, coins shops, daily rewards.
- Landscape or iPad layout.
- Multiplayer.
- Flower pots, yarn, wooden wagon, orange tabby as the player.
- A fourth lane, or fanning lanes that pivot at the screen edge.
- Pixel-speed caps that make objects brake at the cat.
- Unity, Unreal, or any engine outside Apple's frameworks. The 3D world is SceneKit (Rex's call, 2026-09-30).

The kitten's look and pose are Rex's to lock (Rex said the cat gets nailed down later). Ask before reworking her model or adding big motion like jump poses.

Sound and music are not designed. Do not invent a soundtrack.

---

## Open questions

Future work should ask, not guess.

1. Cat's name, if any.
2. Sitting or laying, small wheels or big, open tray or sealed wrap.
3. Game title: Cat Cart, or something with the cat's name.
4. Cozy quiet or louder arcade, once sound exists.
5. Whether the cubby tree or the long runway is the train.

---

## Done when a slice matches this file

A look or feel change is done when:

- A first-time player can swipe, jump a coyote, ride a tree, and grab food without a tutorial dump.
- Objects and the ground still rush at the cat, never brake.
- Worlds still last about 10 seconds and you drive into the next one, no full-screen cut.
- The cat still reads as a grayish lilac British Shorthair kitten in a light-blue 12-pack cart.
- Rex's chosen art, if he has picked, is what is on screen.

---

## For later sessions

`GameScene.swift` is the game: world, rules, camera, input. `Scenery.swift` builds each world's roadside from the models in `CatCart/Models`. `Hud.swift` is the flat layer on top. `CatCartApp.swift` only hosts it. Pictures and textures live in `Assets.xcassets`. Spare takes live in `art/options`.

Everything on the track moves by the same `dz` each frame. Keep it that way. Every 3D material goes through `applyLook` so it gets the bend and the fog; a material that skips it will float above the horizon and never fade. A mesh merged with `flattenedClone` starts with no materials and picks up its pieces' ones later, so call `applyLook` on the pieces before merging (the cat tree and low things do). Calling it on the merged node finds nothing, and the obstacle floats unbent over the far road until it is close (fixed 2026-10-04). When you change art, put extras in the options folder and say which imageset is the live default.

Screenshot check: `scripts/e2e_visual.sh`. `CATCART_GOD=1` turns off crashes, `CATCART_PILOT=1` jumps and rides on its own, `CATCART_WORLD=jungle|house|farm` picks the start world. `CATCART_STATS=1` shows frame rate and draw counts. `CATCART_SWIPES="2:left,3.5:up"` plays swipes at those seconds through the real touch code; `"4:stumble"` trips her, to see the bottle. `"6:tap"` is a finger down and up in place; `"5:press"` and `"7:release"` hold a finger down between them, for testing a touch that's still down when she crashes. Without god mode, two stumbles about half a second apart crash her, which is the easy way to reach the death panel. With it set, each swipe and stumble prints a `CATCART` line with the run time, lane, height, and the top she's riding; the run time reads about 0.08 s behind the swipe time, which counts from launch. `CATCART_TIME=200` starts each run that many seconds into the difficulty ramp. `CATCART_WAVE=31` plays only that obstacle mix (its index in `waves`), back to back. With `CATCART_SWIPES` set, each mix also prints where each thing in it reaches her (in meters run, and the swipe lines show meters too), and a line each time she gets on a tree or back on the road, so a line can be timed by distance. `CATCART_MIRROR=0` and `CATCART_ROT=0` fix how a mix is flipped and turned, so a scripted line knows which lane is which. `CATCART_PERF=1` also prints every tree, coyote, or can built mid-run (a pool that ran dry). `CATCART_SWIPES="4:rocket"` (or `magnet`, `pounce`, `lives`) gives her that power-up, and prints `power`, `rocket landing`, and `saved by nine lives` lines. `CATCART_POWEREVERY=4` puts a power-up in a mix every 4 s; `CATCART_POWER=rocket` makes every one that kind. The pilot only jumps and ducks and never steers, so without god mode it dies on blocked lanes by design. It's still a fair check for a mix with no blocked lane: force it with `CATCART_WAVE` at `CATCART_TIME=200`, and a crash (printed to the console with the mix number) means that mix broke the same-lane gaps. Mixes with blocked lanes are checked by hand.

If you add a mechanic, write the player-facing rule here in the same commit.
