# Cat Cart PRD

Read this before changing look, feel, art, or mechanics. If a request fights this file, ask. Do not silently overwrite a locked call.

Owner: Rex. Player: his mom. The game is a gift, not a store product yet.

Working title: Cat Cart. Bundle: `com.rexchao.catcart`. iPhone only, portrait, one SwiftUI window. The world is real 3D in SceneKit. The kitten, her La Croix cart, coyotes, and wet-food cans are 3D models. The HUD is a SpriteKit layer on top.

---

## The game

A portrait 3-lane endless runner, like Subway Surfers seen from behind the character.

You are a round-faced lilac British Shorthair kitten, about six months old, sitting in a custom-fit La Croix 12-pack box with wheels. You roll down a path that keeps changing worlds. Coyotes come at you. Jump them. Low things hang across a lane. Duck into the box to pass under. Cat trees sit in a lane like trains. Jump on and ride the top. Grab cans of wet food. Last as far as you can. Best distance is saved on the phone.

It should feel easy to pick up in an ad, then fair once you are playing. One thumb. Swipe. No menus to learn before the first run.

---

## Who it is for

Mom, on an iPhone, in portrait, probably on the couch. Big readable objects. Generous jump window. A crash should feel silly, not punishing. The cat is cute. The coyotes are mean on purpose, so the cute/danger contrast is the joke.

Rex is learning while we build. Teaching comments in the Swift files stay. Do not turn this into an engine or a framework.

---

## Locked look

These came from Rex. Treat them as the product, not sketches.

### The cat

Lilac British Shorthair kitten, about 6 months, modeled on Rex's real cat. Natural proportions: round head with full cheeks, small cupped ears, golden eyes, a sturdy seated body with distinct front legs (Rex's call, 2026-10-03, replacing the oversized cartoon head). Coat is warm dove gray with only a faint dusty-lilac cast. Not purple. Not a Russian Blue. Camera is behind her for the run, so the silhouette is the back of her round head and shoulders over the box rim.

Default pose is sitting in the box. Laying-down takes exist so Rex can compare. Do not switch the in-game pose until he says which one stays.

### The cart

A real La Croix sparkling-water 12-pack: the short, flat cardboard case, icy baby-blue wrap, navy script on the back. It is a custom box that fits him. He sits in it. Wheels on the four corners. Small wheels and big wheels were both generated so Rex can pick.

The box says LaCroix in navy brush script with "SPARKLING WATER" under it, on an icy-blue wrap with waves and fizz (Rex's call, 2026-09-30: the real name, not Sparkle Wave). The lettering is set in type by `scripts/make_cart_textures.py`, never by an image generator. Four cans stand in the corners. The real brand name is fine for a family gift; it would have to change before any App Store release.

In the game the cart is 3D (`CatCart/KittenCart.swift`): cardboard walls, the logo on the back and front, four spinning wheels. The kitten's source is Rex's Blender model, `art/models/kitten/cat.blend`. `scripts/blender/export_kitten.py` turns it into the game model (drops the strand fur, cuts it to about 23k triangles, splits it into the parts the game animates), and `scripts/build_kitten.swift` writes `cat_kitten.scn` with the in-game colors. Edit the .blend, then rerun both. The old cartoon kitten is `art/options/player/kitten-cartoon.scn`, built by `scripts/blender/make_cat.py`. Her tail is held up so the name on the back stays readable. The photos themselves are never committed or uploaded.

### Obstacles and pickups

Coyotes replace crates and flower pots. They look dangerous: lean, ragged, bared teeth, amber eyes. Their faces move (snarl cycle). You jump over them. You do not land on them.

Pots are gone. Do not bring them back unless Rex asks.

Low things are the duck obstacles (Rex's call, 2026-10-04). One per world, each built in code in `makeLowThing` in `GameScene.swift`: a striped construction scaffold in the city, a mossy log on two stumps in the jungle, a table with a red gingham cloth in the house, a clothesline with a blue sheet on the farm. Each fills one lane, has open space under it down to the road, a shadow strip on the road, and its bottom edge at 1.38 m, between her ducked head (about 1.25 m) and her sitting head (about 1.68 m). Coyotes stay jump-only; there is no leaping coyote.

Yarn is gone. Collectibles are small cans of wet cat food, big enough to read as food. The current can has a turquoise wrap, white salmon symbol, open silver lid, and visible salmon in gravy. The turquoise distinguishes it from the tan and brown coyotes.

The food source is `art/models/food/wet-food.blend`; the coyote source is `art/models/coyote/coyote.blend`. Run `scripts/build_art.sh` after editing them. It exports lightweight meshes into `wet_food.scn` and `coyote_run.scn`, embeds the food label, and gives the coyote a gallop and snapping jaw. The render-only fur and studio stay out of the game. `swift scripts/check_game_art.swift` checks the exports and renders previews. The old coyote is saved in `art/options/coyote/coyote-original.scn`.

### Cat trees

These are the Subway Surfers trains. A cat tree occupies one lane, with a flat carpeted top the cart can roll on. Sisal posts, cubbies, hanging toys are fine as long as the rideable roof is obvious.

This is the hard piece. The sprite, the lane width, and the ride length have to agree. If the tree looks like a tall tower you smash into, or like a rug with no height, it is wrong.

### Worlds

The run travels through four places, in this order, looping:

1. Streets of a big city
2. Jungle
3. Inside a house
4. Farm

Each world lasts about 10 seconds. You drive into the next one: the road ahead turns into the next place, and the sky, fog, and light blend over as the border comes at you, finishing as the cat crosses it. Nothing fades or cuts on the whole screen at once (Rex's call, 2026-09-30, replacing the old crossfade).

The worlds are built from 3D model kits (free CC0 kits, listed in `art/models/SOURCES.txt`), in one bright, chunky cartoon style like Subway Surfers. The road is a flat textured strip per world. The sky is a painted gradient whose bottom matches the fog color, so the far road melts into it.

### UI

Casual, creamy, icy-blue, paw ornaments. HUD is two pills: distance in meters, food count. The home screen looks at her face from the front: big white "Cat Cart" title in chunky rounded type with a navy outline, a one-line hint, a glossy "Tap to play" button with the paw on its end, and the best distance. Tapping swoops the camera around behind her and the run starts. Death dims the world and pops a rounded panel: a pink "Oh no!" ribbon, meters and food as two big numbers, the best distance, and a gold "New best!" sticker when she beats it. A "Dash again" paw button sits under it, and tapping runs again without going home. The pills hide while the panel is up. No tiny type. No clutter. Extra panel and button takes live in `art/options/ui` for Rex to delete.

---

## Locked feel

Copy Subway Surfers where it matters. Invent around the cat, not around the camera.

### Camera and speed

Behind the cat, a little above, three lanes. The road bends down over a hill in the distance ("curved world", a shader on every 3D thing), and fades into fog, like Subway Surfers. Objects come over the crest small, grow, and rip past the camera. They must not slow down at the cat or behind him.

The cat never moves forward. The whole track (road, scenery, coyotes, food, trees) slides toward the camera at one speed. If a cobble and a coyote at the cat's feet leave the screen at different times, the motion is broken.

Do not cap motion in screen pixels. Tune with `runSpeed()` in meters per second: 17 m/s at the start, rising to 30 over about three minutes. It climbs fast early and settles (about 21 at 30 s, 24 at 1 min, 28.5 at 2 min). Things appear about 118 m ahead, inside the fog.

The camera trails the cat: it follows her lane partway, rises when she rides a tree, rolls a touch on lane changes, and widens a little as the run speeds up.

### Lanes

Three readable tracks at the cat. Tight at the horizon. The cart fits in one lane and does not spill into neighbors. Swipe left or right to change lane. A little tilt on the cart is enough.

### Jump

Swipe up to jump. The jump is a real arc: up to about 1.9 m and back down under gravity. How long she stays in the air is not locked; tune it freely (`jumpAirtime` in `GameScene.swift`, Rex's call 2026-10-03). Today it is 0.8 s at the start and quickens to about 0.66 s at top speed, so it never carries her over half the road. Keep the obstacle spacing longer than a jump plus a moment to react (see Getting harder). A swipe up just before she lands (under 0.2 s) is remembered and she jumps the moment she touches down. Swipe down mid-air to drop fast. Jumping onto a cat tree keeps the arc going, so she comes down on the roof at the end of it, not the instant she reaches the tree. If she catches the roof low, she hops up onto it. (Rex's call, 2026-09-30: the old 1.15 s held hang stayed in the air too long and snapped down onto trees.)

Jumping is how you clear coyotes. Jumping onto a cat tree is how you ride.

### Duck

Swipe down on the ground and she ducks into the box for 0.45 s: her body squashes down inside the box, so only her ears, the top of her head, and her tail tip show over the rim. Then she pops back up with a little springy overshoot. Swipe down again while ducked to keep ducking. Swipe down in the air only brings her down fast; it never ducks (Rex's call, 2026-10-04: the 0.8 s duck lasted too long and the air swipe should just land). Swipe up while ducked and she pops straight into a jump. Lane changes keep the duck going. Ducking works on a tree roof too, but low things only stand on the ground lanes.

A low thing in her lane crashes her unless she is ducked near the ground. Jumping into one is a crash. Ducking does not help against coyotes or a tree front.

Until she has ducked under her first low thing, ever, a bobbing "Swipe down to duck!" line shows below the cart as one comes (about 2 s out). It retires for good after the first success (`duckedUnderOnce` in UserDefaults).

### Cat trees, like trains

- A tree fills one lane for a stretch of depth.
- Hit the front at ground height: crash.
- Jump as the front arrives: land on the roof and stay up without holding jump.
- Ride until the back of the tree passes, then drop to the ground.
- Swipe to a neighbor lane that also has a tree: stay up.
- Swipe to a lane with no tree: fall. If a coyote is there, crash.
- Swipe into the side of a tree from the ground: bump off it and stay in your lane. No crash.
- Jump from a tree to hop to another tree or to clear something.

Never block all three lanes with no jump, duck, or ride out. Two trees plus a food lane is fine. Three coyotes is a forced jump, and three low things a forced duck, both used rarely.

### Getting harder

Like Subway Surfers: easy to start, harder the longer you last, and still fair at top speed.

- One difficulty ramp drives everything: speed, gaps, the jump, and which obstacle mixes show up.
- The first 15 s or so are easy mixes only: one coyote, one tree, food lines. Medium mixes (two busy lanes, short slaloms, coyote then tree, and the first low things to duck) join at about 15 s. Hard mixes (back-to-back coyotes, tree hops, a staircase of trees, jump then duck then jump, lanes that flip between jump and duck, the rare three-coyote wall and three-low-thing wall) join at about 40 s. Easy mixes thin out but never vanish.
- Spacing is in time, not meters. A mix plays out the same at any speed, and the breather between mixes shrinks from 1.75 s to 1.05 s.
- Fairness rule: every lane of every mix can be survived by staying in it and jumping or ducking. Two things in one lane are at least about 1.1 s apart, and a low thing after a coyote at least 1.4 s, since a late jump has to land before the duck swipe. Steering is the easier way through, never the only way. Low things never stand beside the middle of a tree, where a rider stepping off would drop into one.
- Cat trees get longer as speed rises, so a ride lasts about the same time.

### Coyotes

Jump over. If you are high enough, or already on a tree, they pass under. If you are on the ground in their lane when they reach you, crash.

### Food

Touch to collect, even in the air or on a tree. +1 food, a little distance bonus, a pop. Food after a coyote in the same lane is a reward for jumping.

### Crash and retry

White flash, shake, haptic, and the cat tips over in her box. "Oh no!" with meters, food, and best. Tap to run again. Best meters live in UserDefaults as `bestMeters3D` (real meters). The 2D build's `bestMeters` counted about 7x faster, so it is not carried over.

### Feedback that stays

Lane-change haptic. Jump haptic. Collect puff. Landing puff and a small squash. Dust from the wheels. The food pill pulses when you grab food. Light speed lines at the screen edges. Every object has a soft shadow. Do not add score-pop spam or screen-wide particle storms. Mom's game, not an arcade cabinet.

---

## Controls

| Input | In a run |
|---|---|
| Swipe left / right | Change lane |
| Swipe up | Jump |
| Swipe down | On the ground, duck into the box. In the air, land now |
| Tap on the home screen or death panel | Start a run |

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
| Player | 3D kitten from `art/models/kitten/cat.blend` (`cat_kitten.scn`) in the 3D La Croix cart |
| Coyote | 3D galloping coyote (`coyote_run.scn`), flat snarl pictures as fallback |
| Food | 3D turquoise salmon can (`wet_food.scn`) |
| Cat tree | cubby tree with a flat roof |
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
- 3D kitten in a 3D La Croix cart: wheels spin, tail sways, ears flick, eyes blink, head leans into turns.
- 3D coyotes with a looping gallop and snapping jaw. Jumpable.
- 3D turquoise wet-food cans, single cans and lines of cans, some sitting on tree roofs.
- Cat trees as real 3D platforms: carpeted roof, sisal posts, cubbies, a pom-pom. Ride, hop to a neighbor tree, fall off the end, bump off the side.
- Duck into the box with a swipe down. One low thing per world to duck under, from about 15 s. A one-time hint teaches it.
- Four worlds built from 3D kits, about 10 s each. You drive into the next one while sky, fog, and light blend.
- Soft shadows, wheel dust, landing squash, trailing camera, speed lines.
- Home screen facing her, swoop into the run. HUD pills, death panel.
- Art options sitting in `art/options` for Rex to prune.

Known gaps against this PRD:

- The kitten has no jump pose; she rides the arc sitting.
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

Screenshot check: `scripts/e2e_visual.sh`. `CATCART_GOD=1` turns off crashes, `CATCART_PILOT=1` jumps and rides on its own, `CATCART_WORLD=jungle|house|farm` picks the start world. `CATCART_STATS=1` shows frame rate and draw counts. `CATCART_SWIPES="2:left,3.5:up"` plays swipes at those seconds through the real touch code. `CATCART_TIME=200` starts each run that many seconds into the difficulty ramp. `CATCART_WAVE=31` plays only that obstacle mix (its index in `waves`). Pilot without god mode is the fairness check: it only jumps and ducks, never steers, so if it crashes, a mix broke the rule above (the crash prints to the console with the mix number).

If you add a mechanic, write the player-facing rule here in the same commit.
