# NeonWastesRPG

Open-world action-RPG in **Godot 4.7.1**. Dark, violent, neo-noir cyberpunk
wasteland — Blade Runner's neon dystopia sunk into Fallout's post-apocalyptic
grit — rendered as **3D cel-shaded comic art**.

---

## 1. Vision and tone

**The pitch.** Forty years after the Cascade, the arcology city of **Ferrum
Halo** still burns its neon while the desert eats the suburbs. You are a
courier with a bad debt, a worse memory, and the only working transit pass
between the tower districts and the wastes. Everyone who can help you wants
something you cannot afford to give.

**Tonal rules — these are load-bearing, not decoration:**

- **Noir means moral cost, not edginess.** Every faction has a defensible
  reason for something indefensible. The player is never handed a clean option;
  they are handed a price list. If a quest has an obviously correct answer,
  it is not finished.
- **Violence is consequential and ugly.** It is quick, it hurts, and it leaves
  people worse. Never comedic, never a spectacle, never the reward. When
  combat is the answer, the writing should register that as a failure of
  something earlier.
- **Wet, lit, and filthy.** The world is rain-slicked, neon-soaked, and
  rusting. The camera should always find a light source and a stain.
- **Nobody explains the world.** Lore lands through signage, overheard radio,
  and what people refuse to say. No codex dumps.
- **Cartoon rendering, adult writing.** The cel-shaded look is not a softener.
  The tension between graphic, readable art and bleak subject matter is the
  game's signature — do not resolve it in either direction.

**Content boundaries.** Adult themes (addiction, exploitation, state and
corporate violence) are in scope and should be handled with weight. Sexual
violence and harm to children are out of scope, including as backstory.

---

## 2. Commands

```bash
godot --version                                    # 4.7.1.stable
godot --headless --path . --import                 # reimport; regenerates the class cache

# Verification — run both before committing
godot --headless --path . --script tools/verify_setup.gd   # input map, shaders, main scene
godot --headless --path . --script tools/soak_test.gd      # physics + synthetic input

python3 tools/verify_mcp.py                        # handshake every server in .mcp.json

godot --path .                                     # open the editor
godot --path . --headless --quit-after 300         # run the game headlessly
```

**Rendering a screenshot on a headless box** (software Vulkan via lavapipe —
correct, but ~2 fps, so keep frame counts low):

```bash
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --path . --resolution 1280x720 --rendering-driver vulkan \
  --script tools/screenshot.gd -- --out=/tmp/shot.png --cam=20,2.2,30 --look=-4,7,0
```

`tools/screenshot.gd --help` is in its header comment: `--cam/--look` for a
detached camera, `--fog=0`, `--glow=0`, `--exposure=` to isolate what you are
looking at.

**Re-running `tools/setup_project_settings.gd` rewrites the input map and
physics layers** using the engine's own serializer. Prefer it over hand-editing
`project.godot`'s `[input]` block — the `Object(InputEventKey, …)` encoding is
version-specific and easy to get subtly wrong.

---

## 3. Architecture

```
scenes/     main.tscn + world/ player/ ui/ props/ characters/
scripts/    player/ world/ quests/ systems/ ai/ ui/ util/
shaders/    *.gdshader + include/*.gdshaderinc
worlds/     chunks/ biomes/ data/     — procedural streaming lives here
quests/     main/ side/ resources/    — quest .tres data
assets/     models/ textures/ audio/ fonts/ materials/
tools/      headless verification + authoring scripts
addons/     godot_ai, godot_mcp (MCP editor bridges)
```

**Rules:**

- **Chunked and modular.** The world streams in fixed-size chunks under
  `worlds/chunks/`. Nothing may assume the whole world is resident. Anything
  that walks every entity in the world is a bug in waiting.
- **Quests are `Resource`s, not code.** A quest is a `.tres` deriving from
  `Quest` (`scripts/quests/quest.gd`) holding objectives, flags and rewards.
  Quest *logic* is data interpreted by the quest system; only genuinely unique
  set-piece behaviour gets a script. This keeps quests diffable, hot-reloadable,
  and writable without touching engine code.
- **`CharacterBody3D` for anything that walks.** The player
  (`scripts/player/player_controller.gd`) is the reference implementation:
  locomotion, camera and interaction probing only. Combat, inventory and
  dialogue are separate systems that communicate by **signal**, never by
  reaching into the controller.
- **Poll physics-critical input, don't only listen for events.** Read
  movement and jump via `Input.is_action_just_pressed` / `is_action_pressed`
  inside `_physics_process`. Handling them solely in `_unhandled_input` means
  `Input.action_press()` cannot drive the character, which breaks automated
  tests, replays, scripted cutscenes and AI-driven bodies.
- **Toon shading is shared, not copy-pasted.** Common lighting maths lives in
  `shaders/include/cel_lighting.gdshaderinc`. New surface shaders `#include`
  it rather than re-deriving the banding.
- **Physics layers are named** (see `[layer_names]` in `project.godot`):
  1 world · 2 player · 3 enemy · 4 npc · 5 interactable · 6 projectile ·
  7 trigger · 8 vehicle · 9 cover · 10 water. Use the names, never bare masks
  in comments.
- **Anything interactable exposes `interact(who)`** and sits on layer 5. The
  player's `InteractRay` finds it and emits `interactable_changed`.

---

## 4. MCP usage rules

Three Godot MCP servers are registered in `.mcp.json` (project scope — Claude
asks for approval once per machine). They overlap deliberately; pick by task.

| Server | Transport | Needs a live editor? | Use it for |
|---|---|---|---|
| `godot-cli` (14 tools) | stdio | no | Running the project, reading debug output, project info, UIDs, launching the editor |
| `godot-ai` (43 tools) | http `127.0.0.1:8000` | **yes** | Live scene surgery: nodes, materials, animation, particles, UI, signals, in-editor tests |
| `godot-editor` (65 tools) | stdio (ws `6505`) | **yes** | Live scene/script reads, runtime queries, screenshots, input simulation |

**When to use live MCP tools vs. editing files:**

- **Edit files directly** for anything that belongs in version control and
  wants review: scripts, shaders, `.tres` materials, quest data, and the
  structural parts of scenes. Files are the source of truth. A diff is
  reviewable; a sequence of tool calls is not.
- **Use live MCP tools** for things that are *hard to get right blind*:
  inspecting an existing scene tree, tweaking a material parameter and looking
  at the result, querying runtime state, reproducing a bug, taking a
  screenshot. Iterating on look-and-feel is exactly what they are for.
- **Write the result back to a file.** After converging on values through live
  tools, persist them into the `.tres`/`.tscn`/`.gd` so the change survives the
  editor session and shows up in the diff.
- **Never let live edits silently diverge from disk.** If you changed the scene
  in the editor, save it before continuing.
- **Prefer `godot-cli` when no editor is running** — it drives the Godot binary
  directly and works headlessly. The other two need the editor open with their
  addon enabled, and will simply report "no editor connected" otherwise.
- **On a headless box, `tools/screenshot.gd` beats the MCP screenshot tools** —
  it needs no editor session.

---

## 5. Style bible

Full version with palette swatches and shader parameter guidance:
[`docs/style_bible.md`](docs/style_bible.md). The short form:

**Palette.** Three families, and nothing else without a reason:

| Role | Colour | Hex |
|---|---|---|
| Neon primary | magenta | `#FF2D95` |
| Neon secondary | cyan | `#00E5FF` |
| Neon accent (rare) | acid yellow | `#F7FF3C` |
| Street light | sodium amber | `#FFAD5C` |
| Shadow tint | cold violet | `#3D2E6B` |
| Rust / grime | oxide brown | `#38200F` |
| Ink (outlines) | near-black plum | `#08050F` |

Neon is **the only saturated thing in frame**. Concrete, rust and cloth stay
desaturated so the signage carries every composition.

**Cel shading.** 2–3 light bands, hard terminator, soft only enough to avoid
aliasing. Unlit surfaces are tinted cold violet, **never crushed to black** —
shape must stay readable in an unlit alley. Rim light in the complementary neon
carries the silhouette; it is the single most important part of the look.

**Ink.** Inverted-hull outlines via `assets/materials/outline_ink.tres` as a
material `next_pass`, scaled by view depth so distant buildings keep the same
ink weight, and faded out past the fog line. Hard-edged meshes tear at split
normals — author smooth normals on anything outlined.

**Composition.** Always a light source in frame. Wet ground for reflections.
Silhouette reads before detail does — if the shape is unclear in black, the
model is wrong.

---

## 6. Rendering gotchas (learned the hard way — do not re-introduce)

- **Any per-light term must be multiplied by `ATTENUATION`.** The shadow-tint
  term in `toon_cel.gdshader` originally used `(1.0 - banded * ATTENUATION)`,
  which goes to *full strength* as a light gets further away. With ~60 lights
  in frame every surface got washed out. The un-lit fraction is
  `(1.0 - banded)` — angle only — and `ATTENUATION` is applied separately.
- **Keep emission in the 2–3 range, not 6–8.** ACES tonemapping desaturates
  high emissive values to white, so a "brighter" neon sign renders as a white
  blob. Let the glow pass do the blooming; `glow_hdr_threshold ≈ 1.05`.
- **Toon specular on large flat surfaces becomes a giant hard disc.** The
  ground plane needs a soft ramp (`spec_softness ≈ 0.4`) and the key light
  needs `light_specular` damped. A `smoothstep` highlight that looks like a
  glint on a prop is a spotlight-sized disc on a 500 m plane.
- **Volumetric fog has a visible boundary at `volumetric_fog_length`.** Beyond
  it the froxel volume just stops, and a high `volumetric_fog_ambient_inject`
  makes the seam obvious as an arc across the sky. Keep density low, length
  long, and lean on depth fog for distance.
- **`class_name` types do not resolve until the class cache is rebuilt.** After
  adding a script with a new `class_name`, run
  `godot --headless --path . --import` or scenes will silently instantiate
  *without their script attached* — `instantiate()` still succeeds. Assert
  `get_script() != null` in tests.

---

## 7. Conventions

- GDScript, tabs, static types wherever the parser can carry them.
- `snake_case` files and members, `PascalCase` classes and nodes, `_` prefix
  for private members.
- Comments explain **why**, never what. Restate nothing the code already says.
- Every new shader gets picked up automatically by `tools/verify_setup.gd`;
  every new gameplay system should get a stage in `tools/soak_test.gd`.
- Deterministic generation takes an explicit seed and stores it, so any bug
  report is reproducible.
