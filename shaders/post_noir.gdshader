shader_type canvas_item;

// Full-screen noir print pass: chromatic aberration, halftone shadow dots,
// animated film grain and a vignette. This is the "printed comic panel" half
// of the look — the cel shader flattens the light, this pass adds the paper.
//
// Applied through a full-rect ColorRect on the PostFX canvas layer in
// scenes/main.tscn. Everything except grain is resolution-independent; grain
// deliberately stays in pixel space so it keeps its tooth at any window size.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

group_uniforms ChromaticAberration;
// Screen-edge channel split. Keep low: it is a printing defect, not a trip.
uniform float aberration : hint_range(0.0, 3.0) = 0.55;

group_uniforms Halftone;
// Ben-Day dots in the shadows. Density fades out toward the midtones so lit
// neon stays clean; shadow areas get the printed-ink texture.
uniform float halftone_strength : hint_range(0.0, 1.0) = 0.16;
uniform float halftone_cell_px : hint_range(3.0, 24.0) = 7.0;
uniform float halftone_shadow_cutoff : hint_range(0.0, 1.0) = 0.42;

group_uniforms Grain;
uniform float grain_strength : hint_range(0.0, 0.4) = 0.055;
// Grain steps at 24 fps like film rather than swimming every frame.
uniform float grain_fps : hint_range(1.0, 60.0) = 24.0;

group_uniforms Vignette;
uniform float vignette_strength : hint_range(0.0, 1.5) = 0.42;
uniform float vignette_start : hint_range(0.0, 1.0) = 0.35;

vec3 noir_hash3(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

void fragment() {
	vec2 centred = SCREEN_UV - 0.5;
	float r2 = dot(centred, centred);

	// Channel split grows toward the frame corners, like a cheap lens.
	vec2 ca = centred * r2 * aberration * 0.045;
	vec3 col;
	col.r = texture(screen_texture, SCREEN_UV - ca).r;
	col.g = texture(screen_texture, SCREEN_UV).g;
	col.b = texture(screen_texture, SCREEN_UV + ca).b;

	float lum = dot(col, vec3(0.299, 0.587, 0.114));

	// Halftone: one dot per cell, dot radius grows as the tone darkens.
	float shadow_mask = 1.0 - smoothstep(
		halftone_shadow_cutoff * 0.5, halftone_shadow_cutoff, lum
	);
	vec2 cell = fract(FRAGCOORD.xy / halftone_cell_px) - 0.5;
	float dot_radius = length(cell) * 1.4142; // 0 centre .. ~1 corner
	float ink = smoothstep(0.9, 0.35, dot_radius);
	col *= 1.0 - halftone_strength * shadow_mask * ink;

	// Vignette, biased toward the bottom of the frame where the street sits.
	float vign = smoothstep(
		vignette_start, 0.72, r2 * (1.0 + vignette_strength)
	);
	col *= 1.0 - vignette_strength * vign;

	// Film grain, stronger in shadow where the eye notices noise.
	float frame = floor(TIME * grain_fps);
	float g = noir_hash3(FRAGCOORD.xy + vec2(frame * 61.7, frame * 83.3)).r;
	col += (g - 0.5) * grain_strength * (1.0 - lum * 0.75);

	COLOR = vec4(col, 1.0);
}
