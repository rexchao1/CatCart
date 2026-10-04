# Wet cat food Blender model

Goal: make an editable wet-food can that is easy to distinguish from the tan and rust coyotes.

Constraints: an open can with a lifted lid, visible gravy and salmon, and a salmon picture on the label. Use saturated turquoise and a large white symbol for distance readability. Save the model in `art/models/food/`; previews belong in `art/options/food/`. Leave game integration for a separate request.

Done when: the Blender file is saved with its materials, the full-size render and small pickup preview are checked, and the model opens in Blender.

- [x] Read the PRD, 3D plan, coyote palette, and existing food pickup size.
- [x] Build the can, label, peeled lid, pull tab, and wet food.
- [x] Render and check the model at large and small sizes.
- [x] Save the option, open Blender, and commit the files.

Checked: full-size render and transparent pickup render, then 64 px and 32 px comparisons against existing coyote art on gray, green, cream, and gold swatches. The turquoise body stays distinct. Fog, motion, and real in-game pickup scale have not been tested. The label is packed into the Blender file, and the studio has its own collection.
