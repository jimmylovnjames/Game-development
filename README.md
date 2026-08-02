# NeonWastesRPG

Open-world action-RPG built in **Godot 4.7.1**. Dark, violent, neo-noir
cyberpunk wasteland — Blade Runner's neon dystopia sunk into Fallout's
post-apocalyptic grit — rendered as **3D cel-shaded comic art**.

> Design and contribution guidance lives in **[CLAUDE.md](CLAUDE.md)**.
> Visual direction lives in **[docs/style_bible.md](docs/style_bible.md)**.

---

## Requirements

- **Godot 4.7.1+** on `PATH` (`godot --version`)
- **Node.js 18+** and **Python 3.11+** — only for the MCP tooling
- On a headless machine, `mesa-vulkan-drivers` + `xvfb` to render screenshots

## Quick start

```bash
godot --headless --path . --import   # build the import + class-name cache
godot --path .                       # open the editor
```

Run the game:

```bash
godot --path .                       # F5 in editor, or:
godot --path . --headless --quit-after 300
```

## Verification

Three headless checks, none of which need a display:

```bash
godot --headless --path . --script tools/verify_setup.gd  # input map, physics, shaders, materials, props, scene, addons, quests
godot --headless --path . --script tools/soak_test.gd     # settle, walk, tap vs held jump, prop drop, crate push
python3 tools/verify_mcp.py                               # MCP servers in .mcp.json
```

Physics runs on **Jolt** (`physics/3d/physics_engine`), switched via
`tools/setup_project_settings.gd` — better rigid-body stacking, continuous
collision detection, and seam-free character movement.

`verify_setup.gd` picks up new shaders and quest resources automatically. New
gameplay systems should get a stage in `soak_test.gd`.

## Screenshots without a display

Software Vulkan (lavapipe) under Xvfb. Correct output, roughly 2 fps — keep
`--frames` low.

```bash
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --path . --resolution 1280x720 --rendering-driver vulkan \
  --script tools/screenshot.gd -- --out=/tmp/shot.png \
  --cam=20,2.2,30 --look=-4,7,0 --hud=0
```

Useful flags: `--cam/--look` (detached camera), `--fog=0`, `--glow=0`,
`--rain=0`, `--postfx=0`, `--exposure=`, `--hud=0`. Full list in the script
header.

## Running on a laptop (and on a Mac)

The district puts ~135 realtime lights and ~1500 mesh instances in front of the
camera with volumetric fog, SSIL, SSAO and glow on top. That is a discrete-GPU
load. `GraphicsSettings` picks a tier at boot from the video adapter and applies
it to the viewport, the environment and every light in the scene.

| Tier | Render scale | MSAA | Volumetric fog | SSIL | SSAO | Lights fade past |
|---|---|---|---|---|---|---|
| `potato` | 0.62 | off (FXAA) | no | no | no | 29 m |
| `laptop` | 0.80 | off (FXAA) | no | no | yes | 48 m |
| `desktop` | 1.00 | 4x | yes | yes | yes | 100 m |

Cel shading, ink outlines and neon are identical at every tier — what changes is
how much atmosphere sits on top and how far away things keep being lit.

Override the detected tier per launch:

```bash
godot --path . -- --quality=laptop     # or potato / desktop
```

or permanently in **Project Settings → Neonwastes → Graphics → Tier**
(`auto` by default). The boot report prints the GPU and the tier it chose, so
check that first if performance is not what you expect.

### macOS notes

You do not need an export to try it — open the project in Godot and press F5.

- **Apple Silicon:** Godot 4.4+ ships a native Metal driver, which is faster
  than Vulkan-through-MoltenVK. Try `godot --path . --rendering-driver metal`.
- **Retina is the quiet killer.** A 1440-wide window is a 2880-wide
  framebuffer, so the 3D pass costs four times what the window size suggests.
  The sub-1.0 render scale on the laptop and potato tiers exists for exactly
  this; the UI still draws at native resolution.
- **Stay on Forward+.** Dropping to `--rendering-method mobile` or
  `gl_compatibility` loses volumetric fog, SSIL and SSAO anyway, and
  `post_ink` / `post_noir` sample the depth texture, which those renderers do
  not provide — the comic ink pass breaks rather than degrades. Lower the tier
  before you lower the renderer.

## MCP servers

Three Godot MCP servers are registered in `.mcp.json` (project scope — your
client will ask to approve them once).

| Name | Tools | Transport | Needs a live editor? |
|---|---|---|---|
| `godot-cli` | 14 | stdio | no |
| `godot-ai` | 43 | http `127.0.0.1:8000/mcp` | yes |
| `godot-editor` | 65 | stdio (ws `6505`) | yes |

Install the servers themselves:

```bash
npm install -g @coding-solo/godot-mcp godot-mcp-server
uv tool install godot-ai
```

The two live-editor servers need their addon enabled — both
`addons/godot_ai` and `addons/godot_mcp` are vendored here and already listed
in `project.godot`. `godot-ai` additionally needs its Python server running;
the editor plugin starts it automatically, or run it by hand:

```bash
godot-ai --transport streamable-http --port 8000 --ws-port 9500
```

See CLAUDE.md § "MCP usage rules" for which server to reach for.

## Layout

```
scenes/     main.tscn + world/ player/ ui/ props/ characters/
scripts/    player/ world/ quests/ systems/ ai/ ui/ util/
shaders/    toon_cel · outline_hull · neon_sign · puddle · hologram ·
            post_noir · rain_streak · rain_splash + include/
worlds/     chunks/ biomes/ data/     — procedural streaming
quests/     main/ side/ resources/    — quest .tres data
assets/     models/ textures/ audio/ fonts/ materials/
tools/      headless verification + authoring scripts
```

## Controls

`WASD` move · `Shift` sprint · `Ctrl` crouch · `Space` jump · `E` interact ·
`F` flashlight · `RMB` aim · `Esc` release mouse · `F3` toggle debug overlay

## Licence

Vendored addons under `addons/` keep their own licences (`godot_ai` and
`godot_mcp` are both MIT).
