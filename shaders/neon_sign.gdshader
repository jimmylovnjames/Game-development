shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

// Neon tubing / signage. Unshaded and pushed well above 1.0 so the Environment
// glow pass blooms it — that bloom is doing most of the work in the wet-street
// look, so keep `energy` high and let tonemapping pull it back.
//
// `dropout` models a dying sign: brief full cuts on top of the fine flicker.

#include "res://shaders/include/cel_lighting.gdshaderinc"

group_uniforms Neon;
uniform vec4 neon_color : source_color = vec4(1.0, 0.176, 0.584, 1.0);
uniform float energy : hint_range(0.0, 32.0) = 6.0;
uniform sampler2D mask_texture : filter_linear_mipmap, hint_default_white;
uniform vec2 uv_scale = vec2(1.0, 1.0);

group_uniforms Flicker;
uniform float flicker_speed : hint_range(0.0, 60.0) = 11.0;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.12;
// Per-instance offset so a street of signs does not pulse in unison.
uniform float phase_offset : hint_range(0.0, 100.0) = 0.0;

group_uniforms Dropout;
uniform float dropout_rate : hint_range(0.0, 20.0) = 0.7;
uniform float dropout_chance : hint_range(0.0, 1.0) = 0.0;
uniform float dropout_floor : hint_range(0.0, 1.0) = 0.06;

group_uniforms Glass;
// A dim body colour so the tube is still visible as an object when unlit.
uniform vec4 tube_color : source_color = vec4(0.08, 0.06, 0.1, 1.0);

void fragment() {
	vec2 uv = UV * uv_scale;
	float mask = texture(mask_texture, uv).r;

	float t = TIME + phase_offset;

	// Fine flicker: smooth noise, so it reads as an unstable ballast rather than static.
	float flicker = 1.0 - flicker_amount * cel_value_noise11(t * flicker_speed);

	// Coarse dropout: hold a value for 1/dropout_rate seconds, cut if it lands
	// under the threshold.
	float slot = floor(t * max(dropout_rate, 0.0001) + phase_offset);
	float roll = cel_hash11(slot);
	float alive = (roll < dropout_chance) ? dropout_floor : 1.0;

	float level = clamp(flicker * alive, 0.0, 1.0);

	ALBEDO = mix(tube_color.rgb, neon_color.rgb, mask);
	EMISSION = neon_color.rgb * energy * level * mask;
	ALPHA = 1.0;
}
