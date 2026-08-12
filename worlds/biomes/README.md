# worlds/biomes

Biome definitions as `Resource`s: which props, palettes, weather and encounter
tables a region uses. Drives the procedural generator.

Each `.tres` here derives from `Biome` (`scripts/world/biome.gd`).
`ChunkStreamer` loads every `.tres` in this directory at startup, so adding a
region is a resource and nothing else — no engine code.

## Selection

Regions are picked by a single scalar field, **urbanisation**, running from
`1.0` in the arcology core to `0.0` out in open desert (see
`scripts/world/biome_map.gd`). Each biome claims a half-open band
`[min_urbanisation, max_urbanisation)`, and the bands must tile `0.0 .. 1.0`
with no gap and no overlap — `tools/verify_setup.gd` fails the build otherwise,
because a gap means chunks that generate as bare ground with only a warning.

| Biome | Band | What it is |
|---|---|---|
| `wastes` | 0.00 – 0.30 | Desert eating the suburbs. Ruins, one dying sign in ten. |
| `rustbelt` | 0.30 – 0.64 | Mid-rise, half-vacant, half the street lamps out. |
| `core_halo` | 0.64 – 1.00 | Ferrum Halo proper. Towers and wall-to-wall neon. |

Splitting a band is how you add a region: narrow an existing one and slot the
new `.tres` into the gap.

## Constraints

Keep `sign_energy` near 2–3. ACES tonemapping desaturates anything higher to a
white blob — the glow pass does the blooming (CLAUDE.md §6).
