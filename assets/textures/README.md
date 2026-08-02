# assets/textures

Large flat colour fields plus hand-placed grime. Avoid photographic albedo; it
fights the flat cel shading.

Procedural NoiseTexture2D resources live here and feed `toon_cel` /
`toon_sidewalk` materials:

| Resource | Use |
|---|---|
| `asphalt_grain.tres` | Fine asphalt tooth (legacy / props) |
| `concrete_grain.tres` | Tower and sidewalk surface variation |
| `grime_mask.tres` | Rust/soot overlay on concrete and sidewalks |

The district ground plane itself uses `shaders/street_ground.gdshader`, which
samples world XZ so a 500 m plane never stretches a single UV tile.
