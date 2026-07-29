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
godot --headless --path . --script tools/verify_setup.gd  # input map, shaders, scene, addons, quests
godot --headless --path . --script tools/soak_test.gd     # physics settle, walk, jump
python3 tools/verify_mcp.py                               # MCP servers in .mcp.json
```

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
`--exposure=`, `--hud=0`. Full list in the script header.

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
shaders/    toon_cel · outline_hull · neon_sign + include/
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
