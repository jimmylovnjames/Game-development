# NeonWastesRPG — Visual Style Bible

The rendering target: **a printed comic panel that happens to be running at
60 fps**. Flat graphic shapes, hard light terminators, inked silhouettes, and a
palette where neon is the only saturated thing in the frame.

Reference axis: *Blade Runner 2049* lighting discipline → *Into the
Spider-Verse* / *Borderlands* mark-making → *Fallout* material decay.

---

## 1. Palette

Neon is a **light source**, not a paint colour. Surfaces are desaturated;
saturation arrives as illumination. This is the single rule that keeps the look
coherent when new art lands.

### Neon (emissive only)

| Name | Hex | Linear-ish RGB | Use |
|---|---|---|---|
| Neon magenta | `#FF2D95` | `1.00, 0.176, 0.584` | Primary signage, faction Ferrum, danger |
| Neon cyan | `#00E5FF` | `0.00, 0.898, 1.00` | Secondary signage, tech, safe/interactable |
| Acid yellow | `#F7FF3C` | `0.969, 1.00, 0.235` | **Rare.** Hazard, quest-critical only |
| Sodium amber | `#FFAD5C` | `1.00, 0.68, 0.36` | Street lamps, fire, habitation |

Magenta and cyan are the load-bearing pair; they read as complements and each
one's rim light pops against the other's fill. Acid yellow is a punctuation
mark — if it is on screen twice in one view, one of them is wrong.

### Surfaces (never saturated)

| Name | Hex | Use |
|---|---|---|
| Wet asphalt | `#131118` | Streets, plazas — low roughness, reflective |
| Concrete | `#4A4A54` | Tower blocks, barriers |
| Oxide rust | `#38200F` | Grime overlay, wasteland structures |
| Cold violet | `#3D2E6B` | Shadow tint — the colour unlit surfaces fall toward |
| Ink | `#08050F` | Outlines. Near-black, plum-biased, never pure `#000` |

### Sky and atmosphere

| Element | Colour | Notes |
|---|---|---|
| Sky zenith | `#0B0818` | Nearly black |
| Sky horizon | `#4F1160` | Sodium/neon haze bounced off the cloud deck |
| Fog | `#3C2153` | Violet, low density — depth cue, not a curtain |

---

## 2. Cel shading

Implemented in `shaders/toon_cel.gdshader` over
`shaders/include/cel_lighting.gdshaderinc`.

**Bands.** 2–3. Three for characters and hero props, two for ground and bulk
architecture. Four or more stops reading as a comic and starts reading as
ordinary smooth shading with artefacts.

**Terminator.** Hard. `band_softness` around `0.03` — just enough to stop the
edge crawling under camera motion. Ground planes can go to `0.06` because
their normals are constant and the band edge is a huge screen-space line.

**Shadow wrap.** `shadow_wrap ≈ 0.35` pushes light slightly around the
terminator. This exists so unlit sides show *form* instead of becoming a
silhouette hole.

**Shadow tint.** `shadow_tint_strength ≈ 0.5` toward cold violet. **Unlit is
never black.** A character standing in an unlit alley must still read as a
character. The tint is applied per-light and multiplied by that light's colour,
so a magenta sign throws magenta shadow — which is most of why the streets feel
lit rather than painted.

**Rim light.** The most important single parameter in the project.
`rim_light_bias` controls how much the rim depends on actual lights:

- `0.0` — rim always on. Maximum readability, most "comic". Use for the player.
- `1.0` — rim only where light lands. Most grounded. Use for bulk architecture.
- `0.35–0.6` — everything else.

Rim colour is normally the *complement* of the surface's dominant fill.

**Specular.** A hard toon blob, small and bright. Beware: the same parameters
that make a nice glint on a prop produce a spotlight-sized disc on a large flat
plane. Ground materials want `spec_softness ≈ 0.4` (a soft ramp) and a low
`light_specular` on the key light.

---

## 3. Ink outlines

`shaders/outline_hull.gdshader`, applied as `next_pass` on a toon material —
see `assets/materials/toon_concrete.tres`.

- Inverted hull: back-faces only, vertices pushed along the normal.
- `constant_screen_width = true` scales the hull by view depth so a tower 200 m
  away has the same ink weight as a crate at 2 m. Without it, outlines
  disappear into the distance and the comic read collapses.
- Faded out between `fade_start` and `fade_end` — a crisp outline on a
  fog-shrouded shape looks like a sticker.
- **Hard-edged meshes tear at split normals.** Author smooth normals on
  anything that gets an outline, or accept seams at the corners.

Not every object is outlined. Outline what the player interacts with and the
mid-ground; leaving distant bulk architecture un-inked builds depth.

---

## 4. Lighting and composition

- **Always a visible light source in frame.** A sign, a lamp, a fire, a window.
  Compositions without one read as under-lit rather than noir.
- **Three-source street kit:** cold moonlight key from above (low energy,
  `light_specular` damped), warm sodium lamps at street level, saturated neon
  signage as accent. The colour contrast between amber and magenta/cyan is what
  makes the street read as a street.
- **Wet ground.** Low roughness on horizontal surfaces so signage smears into
  reflection. This is doing an enormous share of the work for free.
- **Glow is the finishing pass.** `glow_hdr_threshold ≈ 1.05`,
  `glow_intensity ≈ 0.95`. Keep emissive materials at energy 2–3 and let the
  bloom carry them; pushing emission to 6+ just tonemaps to white.
- **Fog is a depth cue, not weather.** Low density. Volumetric fog adds shafts
  around neon, but has a hard boundary at `volumetric_fog_length` — keep the
  length long and the density low so that seam never shows.
- **Silhouette first.** If the shape is unreadable as a black cut-out, no amount
  of shading fixes it.

---

## 5. Modelling guidance

- Chunky, low-poly-adjacent forms with exaggerated proportion. Silhouette over
  surface detail — the shader flattens surfaces anyway.
- Bevel every hard edge slightly. Cel shading and inverted-hull outlines both
  fall apart on perfectly sharp corners.
- Detail belongs in the silhouette (aerials, cables, torn cladding, hanging
  signage), not in the normal map.
- Textures: large flat colour fields plus hand-placed grime. Avoid photographic
  albedo — it fights the flat shading. The `grime_texture` / `grime_up_bias`
  channel on `toon_cel` exists so untextured blockout geometry still reads as
  post-apocalyptic.

---

## 6. Current world

`scripts/world/chunk_streamer.gd` builds the world as 64 m chunks around the
player: greybox towers, hung neon signage with per-sign flicker phase,
cantilevered sodium street lamps, rubble lots, and a central plaza at the
origin. What a region looks like is `Biome` data in `worlds/biomes/`, not code.

Two constraints the look depends on:

- **Lights are ringed.** Only chunks inside `detail_radius` keep their
  `Light3D`s; the rest keep their emissive signage and go dark. A full load ring
  of lit chunks is well over a hundred lights in frame, and the cel bands go
  flat under that (see CLAUDE.md §6).
- **Nothing is permanent.** Chunks outside the load ring are freed. Gameplay
  code must not hold a reference to anything the generator spawned.
