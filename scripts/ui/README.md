# scripts/ui

Controllers for the scenes in `scenes/ui/`.

`touch_controls.gd` is the on-screen Android HUD. It feeds the input map
(`move_*`, `jump`, `sprint`, `interact`, …) and emits `look_delta` for the
camera; GameRoot wires that to `PlayerController.apply_look()`. Hidden on
headless runs and on mouse-only desktops unless you pass `--touch=1`.
