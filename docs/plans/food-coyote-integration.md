# Food and coyote game integration

Goal: build Cat Cart with the saved Blender food and coyote models in the running game.

Constraints: export the current saved `.blend` files without rebuilding over edits. Keep pickup rules, obstacle timing, and jump tuning. Preserve the coyote's gallop and snarl, and the food's bob. Strip studio and strand fur from game exports. Keep unrelated working files intact.

Done when: both models are bundled and visible in SceneKit, coyote clones animate, food is collectable, and the simulator build and visual run pass.

- [x] Read the source exporters, SceneKit loader, pickup code, and project checks.
- [x] Export lightweight game meshes, materials, and coyote animation.
- [x] Load the 3D food and updated coyote in the game.
- [x] Check the exported assets and animation, build, and inspect a simulator run.
- [x] Update the art instructions and commit the build-ready project.

Export sizes: coyote 23,824 triangles with 12 animated parts; food 5,938 triangles. The label is embedded as image data. SceneKit previews checked the gallop on cloned coyotes and both jaw poses. Simulator screenshots show the turquoise cans in all four worlds and a collected can in the HUD. The close-up preview caught reversed vertical texture coordinates, corrected before the final build.

Final checks passed: `scripts/build_art.sh`, `swift scripts/check_game_art.swift`, `scripts/e2e_visual.sh`, and the final Xcode simulator build after correcting the label. The corrected label was inspected in a close-up SceneKit render, and the rebuilt app was installed and launched again. Physical iPhone performance is not checked.
