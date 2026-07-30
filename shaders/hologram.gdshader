shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Failing holographic ad-board. Additive so the dark bands between scanlines
// read as air, not glass. Scanlines crawl upward, the whole panel flickers
// like a dying ballast, and random horizontal strips shear sideways on glitch
// beats. Fresnel brightens the rim so the panel edges read as a light source
// from across the street.

#include "res://shaders/include/cel_lighting.gdshaderinc"

group_uniforms Holo;
uniform vec4 holo_color : source_color = vec4(0.0, 0.898, 1.0, 1.0);
uniform float energy : hint_range(0.0, 8.0) = 2.2;
// Per-instance offset so neighbouring boards never pulse in unison.
uniform float phase_offset : hint_range(0.0, 100.0) = 0.0;
uniform vec2 uv_scale = vec2(1.0, 1.0);

group_uniforms Scanlines;
uniform float scanline_density : hint_range(2.0, 120.0) = 34.0;
uniform float scanline_speed : hint_range(-4.0, 4.0) = 0.55;
uniform float scanline_sharpness : hint_range(0.02, 1.0) = 0.3;

group_uniforms Flicker;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.18;
uniform float flicker_speed : hint_range(0.0, 60.0) = 9.0;

group_uniforms Glitch;
// Glitch beats per second, and how far strips shear in UV.
uniform float glitch_rate : hint_range(0.0, 30.0) = 3.5;
uniform float glitch_chance : hint_range(0.0, 1.0) = 0.22;
uniform float glitch_strength : hint_range(0.0, 0.4) = 0.06;

group_uniforms Edges;
uniform float edge_boost : hint_range(0.0, 4.0) = 1.1;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.4;

varying vec2 v_uv;

void vertex() {
	v_uv = UV * uv_scale;
}

void fragment() {
	float t = TIME + phase_offset;

	vec2 uv = v_uv;

	// On glitch beats, shear a few random horizontal strips sideways.
	float slot = floor(t * glitch_rate);
	float roll = cel_hash11(slot * 0.731);
	if (roll < glitch_chance) {
		float strip = floor(uv.y * 24.0);
		float shear = cel_hash11(slot + strip * 13.7) - 0.5;
		uv.x += shear * glitch_strength * step(0.6, cel_hash11(strip * 3.3 + slot));
	}

	// Bright scanlines crawling up the board, with a finer dark interleave so
	// the panel never sits at one flat brightness.
	float scan = sin((uv.y * scanline_density - t * scanline_speed) * 6.28318);
	float lines = mix(1.0, smoothstep(-scanline_sharpness, scanline_sharpness, scan), 0.75);
	float interleave = mix(1.0, step(0.5, fract(uv.y * scanline_density * 4.0)), 0.15);

	float flicker = 1.0 - flicker_amount * cel_value_noise11(t * flicker_speed);

	float fres = cel_fresnel(NORMAL, VIEW, fresnel_power);

	float intensity = lines * interleave * flicker;
	vec3 col = holo_color.rgb * energy * (intensity + fres * edge_boost);

	ALBEDO = col;
	// Additive blending keys transparency off brightness; alpha stays opaque
	// so the depth pass ordering does not fight the glow pass.
	ALPHA = 1.0;
}
