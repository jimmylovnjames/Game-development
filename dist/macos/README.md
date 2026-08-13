# Play NeonWastesRPG on a MacBook

This is a **playtest installer**, not a signed App Store build. It downloads
the official Godot 4.7.1 universal editor (Apple Silicon and Intel), imports
this project, and puts a launcher in `~/Applications`.

## Fastest path

1. Clone or download this repository.
2. In Finder, double-click **`Play on Mac.command`** at the repo root.
3. If macOS warns that it cannot be opened, **right-click → Open → Open**.
4. Wait through the first-time Godot download (~160 MB) and import.
5. `NeonWastesRPG` launches from `~/Applications`. Keep that app; re-run the
   installer later to update.

### One-liner (no clone yet)

```bash
curl -fsSL https://raw.githubusercontent.com/jimmylovnjames/Game-development/claude/godot-cyberpunk-rpg-setup-xqy75h/dist/macos/install.sh | /bin/bash
```

To install a specific branch:

```bash
NEONWASTES_REF=your-branch-name /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jimmylovnjames/Game-development/claude/godot-cyberpunk-rpg-setup-xqy75h/dist/macos/install.sh)"
```

## After it is installed

| | |
|---|---|
| Play | `~/Applications/NeonWastesRPG.app` (or Spotlight “NeonWastesRPG”) |
| Editor | ` /bin/bash dist/macos/install.sh --editor` |
| Reinstall engine | ` /bin/bash dist/macos/install.sh --reinstall` |
| Remove playtest | ` /bin/bash dist/macos/install.sh --uninstall` |
| Log | `~/Library/Logs/NeonWastesRPG.log` |

## Controls

`WASD` move · `Shift` sprint · `Ctrl` crouch · `Space` jump · `E` interact ·
`F` flashlight · `RMB` aim · `Esc` release mouse · `F3` debug overlay

## MacBook Air notes

- **M1 / M2 / M3 / M4 Air** is the target. The Godot build is universal, so
  late Intel Airs work too, but Forward Plus + volumetric fog will run hotter.
- The launcher opens **windowed and maximised** so a 13-inch display does not
  spawn a 1920×1080 window off-screen.
- The first minute can hitch while shaders compile. That is expected.
- If the fan ramps, drop to the debug overlay (`F3`) and check fps. Closing
  other apps helps more than a graphics settings menu (there is not one yet).

## Gatekeeper

The launcher is **ad-hoc signed on your Mac**. Apple did not notarize it.

- Right-click the app → **Open** the first time.
- Or: System Settings → Privacy & Security → **Open Anyway**.
- Quarantine is cleared for you (`xattr`). You should not need
  `spctl --master-disable`.

## Native `.app` zip from CI

Pull requests also run `.github/workflows/macos-playtest.yml`, which exports a
standalone `NeonWastesRPG-macos.zip` (Godot export templates, ad-hoc signed).
Download it from the Actions tab, unzip, move `NeonWastesRPG.app` out of
Downloads into `/Applications` or `~/Applications`, then right-click → Open.

That zip is a built game, not the editor. The double-click installer above is
the one that always matches the folder you are standing in.
