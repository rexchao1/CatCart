# Plan: pick your cat and your cart

Goal: on the home screen you pick which cat rides and which cart she rides in. The lilac kitten in the La Croix box stays the default. Everything is open from the start, no unlocking.

Asked by Rex on 2026-10-08: "add in more characters to choose from. And you can choose a certain cart." He chose new cat models (not recolors of her), new cart shapes (not new wraps), and all open from the start. Then he asked for Bean, a real cat, from a photo.

## The cats

All are kittens about her age, sitting up, built by the same Blender script as hers (`scripts/blender/make_kitten_v4.py` with `--breed`), so they keep her parts, her animations, and her shell fur. Each breed changes the head, ears, muzzle, body, fur length, coat pattern, and eye, nose, and ear colors.

| id | Name on screen | Look |
|---|---|---|
| lilac | Lilac | Her. Unchanged, the default. |
| bean | Bean | A real cat named Bean, from a photo Rex shared (the photo is never committed). A British Shorthair like Lilac, so her round face, cheeks, and small ears, but a brown-silver classic tabby: an M on the forehead, stripes on the cheeks, back, legs, and tail, a pale muzzle and chin, hazel eyes (green rim, amber center), a brick-pink nose. He. |
| ginger | Ginger | Orange mackerel tabby shorthair: stripes on the back, legs, and tail, an M on the forehead, white chin, green-gold eyes, pink nose. |
| tux | Tux | Tuxedo: black coat, white muzzle, bib, belly, and paws, green eyes, a black nose. |
| siamese | Miso | Siamese: cream body, seal-brown mask, ears, paws, and tail, blue eyes, a finer face and bigger ears. |
| fluffy | Fluffy | Maine Coon kitten: long brown tabby fur, a big ruff, lynx tips on the ears, a bushy tail, amber eyes. |

## The carts

Same footprint and rim height as the box, so lanes, the duck, and every collision stay as they are. Built in code in `KittenCart.swift`, like the box.

| id | Name on screen | Look |
|---|---|---|
| lacroix | La Croix | The 12-pack box. Unchanged, the default. |
| basket | Laundry Basket | A mint plastic laundry basket with slotted sides and rounded corners, on swivel casters. |
| wagon | Red Wagon | A red metal toy wagon tub with a rolled rim, big white-wall wheels, and its handle folded back over the front. |
| bed | Cat Bed | A round plush donut bed, pink with a cream lining, on little wooden wheels. |

## Rules

- The choice is saved on the phone (`catChoice`, `cartChoice` in UserDefaults) and kept for the next launch.
- Home screen: two pills over "Tap to play", one for the cat and one for the cart, each with arrows. Tapping an arrow changes it at once; the home camera already looks at her face, so you see the new cat and cart right away. Swiping left or right on the home screen changes the cat.
- A run starts on a tap that lifts without swiping, anywhere off the pills. (It used to start on touch-down.)
- Swaps only happen on the home screen, never mid-run (`docs/plans/performance.md`).
- Every cat fits the duck heights in `docs/plans/duck.md`: ducked, the top of her head stays under `lowClearance` (1.38 m). Sitting, she stays under about 1.7 m so the camera framing holds.

## Done when

- All six cats and four carts show on the home screen and in a run, in the simulator.
- `swift scripts/check_game_art.swift` passes for every cat model.
- Duck heights are checked for each cat.
- The PRD describes the picker, the cats, and the carts.

## Steps

| # | Step | State |
|---|---|---|
| 1 | Choice plumbing: `CatChoice`/`CartChoice`, saved, KittenCart can swap cat and cart | done |
| 2 | Home picker pills, tap-on-lift start, swipe to change cat | done (taps on the pills not yet tried by hand) |
| 3 | Three new carts built in code | done, checked in the simulator (home and run) |
| 4 | Breed profiles in the kitten script; per-breed colors through the exporter and `build_kitten.swift` | todo |
| 5 | Build the five new cats (Bean first), look at their renders, fix what reads wrong | todo |
| 6 | Duck heights and art check for each cat; simulator screenshots | todo |
| 7 | PRD and AGENTS.md updates | todo |
