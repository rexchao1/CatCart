# Cat Cart PRD

Read this before changing look, feel, art, or mechanics. If a request fights this file, ask. Do not silently overwrite a locked call.

Owner: Rex. Player: his mom. The game is a gift, not a store product yet.

Working title: Cat Cart. Bundle: `com.rexchao.catcart`. iPhone only, portrait, one SwiftUI window. The 2D SpriteKit build is live. The world is moving to 3D in SceneKit (see `docs/plans/3d-world.md`).

---

## The game

A portrait 3-lane endless runner, like Subway Surfers seen from behind the character.

You are a round-faced lilac British Shorthair kitten, about six months old, sitting in a custom-fit La Croix 12-pack box with wheels. You roll down a path that keeps changing worlds. Coyotes come at you. Jump them. Cat trees sit in a lane like trains. Jump on and ride the top. Grab cans of wet food. Last as far as you can. Best distance is saved on the phone.

It should feel easy to pick up in an ad, then fair once you are playing. One thumb. Swipe. No menus to learn before the first run.

---

## Who it is for

Mom, on an iPhone, in portrait, probably on the couch. Big readable objects. Generous jump window. A crash should feel silly, not punishing. The cat is cute. The coyotes are mean on purpose, so the cute/danger contrast is the joke.

Rex is learning while we build. Teaching comments in `GameScene.swift` stay. Do not turn this into an engine or a framework.

---

## Locked look

These came from Rex. Treat them as the product, not sketches.

### The cat

Lilac British Shorthair kitten, about 6 months. Huge round head, chubby cheeks, tiny ears, compact body. Coat is dove gray with only a faint dusty-lilac cast. Not purple. Not a Russian Blue. Camera is behind him for the run, so the silhouette is the back of that round head over the box rim.

Default pose is sitting in the box. Laying-down takes exist so Rex can compare. Do not switch the in-game pose until he says which one stays.

### The cart

A real La Croix sparkling-water 12-pack: the short, flat cardboard case, icy baby-blue wrap, navy script on the back. It is a custom box that fits him. He sits in it. Wheels on the four corners. Small wheels and big wheels were both generated so Rex can pick.

The generated wrap currently says Sparkle Wave, not La Croix. That is a stand-in because the image model garbles brand lettering. The look we want is still La Croix. If Rex wants the real word on the box, put it on in code or a real label, do not hope the generator spells it.

### Obstacles and pickups

Coyotes replace crates and flower pots. They look dangerous: lean, ragged, bared teeth, amber eyes. Their faces move (snarl cycle). You jump over them. You do not land on them.

Pots are gone. Do not bring them back unless Rex asks.

Yarn is gone. Collectibles are small cans of wet cat food, big enough to read as food (open lid, gravy or jelly, a chicken or salmon picture on the label).

### Cat trees

These are the Subway Surfers trains. A cat tree occupies one lane, with a flat carpeted top the cart can roll on. Sisal posts, cubbies, hanging toys are fine as long as the rideable roof is obvious.

This is the hard piece. The sprite, the lane width, and the ride length have to agree. If the tree looks like a tall tower you smash into, or like a rug with no height, it is wrong.

### Worlds

The run travels through four places, in this order, looping:

1. Streets of a big city
2. Jungle
3. Inside a house
4. Farm

Each world lasts about 10 seconds. The change to the next one is a long, smooth crossfade, not a cut. The ground and the sides have to keep moving during the fade so it does not feel like a slide show.

### UI

Casual, creamy, icy-blue, paw ornaments. HUD is two pills: distance in meters, food count. Title and death sit on a rounded panel with a paw button. No tiny type. No clutter. Extra panel and button takes live in `art/options/ui` for Rex to delete.

---

## Locked feel

Copy Subway Surfers where it matters. Invent around the cat, not around the camera.

### Camera and speed

Behind the cat, three lanes, path pinching toward a vanishing point. Objects spawn small and far, grow, and rip past the camera. They must not slow down at the cat or behind him.

World depth is constant-z. Screen position is 1/z. Far things crawl. Near things rush. Same math for coyotes, food, trees, roadside props, and the ground strips. If a cobble and a coyote at the cat's feet leave the screen at different times, the motion is broken.

Do not cap motion in screen pixels. Tune arrival time with the seconds-to-cat number in `zSpeed()`, today about 1.45s at the start of a run, speeding up as you survive.

### Lanes

Three readable tracks at the cat. Tight at the horizon. The cart fits in one lane and does not spill into neighbors. Swipe left or right to change lane. A little tilt on the cart is enough.

### Jump

Swipe up to jump. Hold the hang (about 1.15s on the ground, a bit less on a tree). Swipe down to slam back down. This is not a timed auto-land hop. If she holds the jump, she stays up. If she swipes down, she drops now.

Jumping is how you clear coyotes. Jumping onto a cat tree is how you ride.

### Cat trees, like trains

- A tree fills one lane for a stretch of depth.
- Hit the front at ground height: crash.
- Jump as the front arrives: land on the roof and stay up without holding jump.
- Ride until the back of the tree passes, then drop to the ground.
- Swipe to a neighbor lane that also has a tree: stay up.
- Swipe to a lane with no tree: fall. If a coyote is there, crash.
- Jump from a tree to hop to another tree or to clear something.

Never block all three lanes with no jump or ride out. Two trees plus a food lane is fine. Three coyotes is a forced jump, used rarely.

### Coyotes

Jump over. If you are high enough, or already on a tree, they pass under. If you are on the ground in their lane when they reach you, crash.

### Food

Touch to collect, even in the air or on a tree. +1 food, a little distance bonus, a pop. Food after a coyote in the same lane is a reward for jumping.

### Crash and retry

White flash, shake, haptic. "Oh no!" with meters, food, and best. Tap to run again. Best meters live in UserDefaults as `bestMeters`.

### Feedback that stays

Lane-change haptic. Jump haptic. Collect puff. Landing puff. Light speed lines. Do not add score-pop spam or screen-wide particle storms. Mom's game, not an arcade cabinet.

---

## Controls

| Input | In a run |
|---|---|
| Swipe left / right | Change lane |
| Swipe up | Jump and hang |
| Swipe down | Land now |
| Tap on the ready or death panel | Start a run |

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
| Player | sitting, small wheels |
| Coyote | 3D snarl open / mid / closed |
| Food | chicken can |
| Cat tree | cubby tree with a flat roof |
| Worlds | city-clear, jungle-path, house-hall, farm-lane |
| UI | paw panel, paw button, hud bar |

If he drops a different PNG onto the matching imageset, that is the new default. Honor it.

Sprites are isolated on a keyable flat color, no baked ground shadow. Worlds are full 9:16 paintings with a path down the middle and a vanishing point in the upper-middle, so the 3-lane math still fits.

---

## What is in the build now

This is the live game, not a wish list.

- SpriteKit scene, portrait, iPhone 17 simulator scheme.
- 1/z track, three lanes, jump hold and slam.
- Coyotes with a 3-frame face snarl. Jumpable.
- Wet food collectibles.
- Cat trees you can ride. Hop to a neighbor tree or fall off the end.
- Four worlds, 10s each, ~1.6s crossfade.
- The world is one 1/z corridor: path down the middle, walls up the sides, same math as the coyotes. Far things crawl. Near things rush. No still lower half.
- The painting only shows through a sky opening at the vanishing point.
- Side props (lamps, crates, plants, doorways) sit on the road edge and rush off the screen.
- World change keeps the corridor moving and crossfades into the next place.
- HUD pills, ready panel, death panel.
- Art options sitting in `art/options` for Rex to prune.

Known gaps against this PRD:

- Box lettering is Sparkle Wave, not La Croix.
- Sitting vs laying and wheel size are not chosen yet.
- Jump still uses the sitting sprite. No wheel spin, no jump pose in the run.
- Coyote faces are three stills, not a harvested video cycle.
- The long-runway cat tree is an extra, not the default. The cubby tree is what the lane math is tuned to.
- No sound.
- App icon is still the old orange tabby.
- Title screen is "tap to dash", not a real home.

---

## Not now

Do not add these unless Rex asks.

- Other characters, hoverboards, missions, coins shops, daily rewards.
- Landscape or iPad layout.
- Multiplayer.
- Flower pots, yarn, wooden wagon, orange tabby as the player.
- A fourth lane, or fanning lanes that pivot at the screen edge.
- Pixel-speed caps that make objects brake at the cat.
- Unity, Unreal, or any engine outside Apple's frameworks. The 3D world is SceneKit (Rex's call, 2026-09-30). Cat, coyotes, and food stay 2D pictures facing the camera until Rex locks the cat stills.

Real character animation (wheels, jump poses, tail) waits until Rex locks the cat and cart stills. He already said that. Ask before spending a generation pass on motion of the cat.

Sound and music are not designed. Do not invent a soundtrack.

---

## Open questions

Future work should ask, not guess.

1. Cat's name, if any.
2. Sitting or laying, small wheels or big, open tray or sealed wrap.
3. Keep Sparkle Wave as a cute fake brand, or put real La Croix lettering on the box.
4. Game title: Cat Cart, or something with the cat's name.
5. Cozy quiet or louder arcade, once sound exists.
6. Whether the cubby tree or the long runway is the train.

---

## Done when a slice matches this file

A look or feel change is done when:

- A first-time player can swipe, jump a coyote, ride a tree, and grab food without a tutorial dump.
- Objects and the ground still rush at the cat, never brake.
- Worlds still last about 10 seconds and fade instead of cutting.
- The cat still reads as a grayish lilac British Shorthair kitten in a light-blue 12-pack cart.
- Rex's chosen art, if he has picked, is what is on screen.

---

## For later sessions

`GameScene.swift` is the whole game. `CatCartApp.swift` only hosts it. Art lives in `Assets.xcassets`. Spare takes live in `art/options`.

When you change motion, match the ground strips and the side props to the same z-speed as the track items. When you change art, put extras in the options folder and say which imageset is the live default.

If you add a mechanic, write the player-facing rule here in the same commit.
