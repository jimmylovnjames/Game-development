shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;

// Rain-filled pothole. Mostly a mirror: near-black face-on, cold sky-violet at
// grazing angles, with animated rain-impact rings and a wind-sheared micro
// ripple tilting the normal so neon signage smears across it in streaks.
//
// The irregular shoreline is cut from world-space noise, so one shared
// material covers every puddle in the district without visible repetition.

#include "res://shaders/include/cel_lighting.gdshaderinc"

group_uniforms Water;
uniform vec4 deep_color : source_color = vec4(0.012, 0.01, 0.02, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.19, 0.11, 0.32, 1.0);
uniform float reflection_strength : hint_range(0.0, 4.0) = 1.4;
uniform float fresnel_power : hint_range(0.5, 10.0) = 3.2;

group_uniforms Ripples;
// One rain impact site per ripple_cell metres of ground.
uniform float ripple_cell : hint_range(0.2, 3.0) = 0.9;
uniform float ripple_ring_speed : hint_range(0.1, 3.0) = 0.9;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.35;
uniform float micro_scale : hint_range(0.1, 20.0) = 3.5;
uniform float micro_speed : hint_range(0.0, 5.0) = 0.7;
uniform float micro_strength : hint_range(0.0, 1.0) = 0.16;

group_uniforms Specular;
uniform float spec_threshold : hint_range(0.0, 1.0) = 0.2;
uniform float spec_softness : hint_range(0.001, 0.5) = 0.12;
uniform float spec_strength : hint_range(0.0, 8.0) = 2.4;

group_uniforms Shoreline;
uniform float shore_noise_scale : hint_range(0.05, 5.0) = 0.55;
uniform float shore_threshold : hint_range(0.0, 1.0) = 0.42;
uniform float shore_softness : hint_range(0.001, 0.5) = 0.16;

varying vec3 v_world_pos;

float ripple_height(vec2 p) {
	vec2 cell = floor(p / ripple_cell);
	vec2 local = fract(p / ripple_cell);
	// Deterministic impact point inside this cell.
	vec2 site = vec2(
		cel_hash11(cell.x * 17.77 + cell.y * 91.31),
		cel_hash11(cell.x * 53.13 + cell.y * 29.97)
	) * 0.6 + 0.2;
	float phase = fract(
		TIME * ripple_ring_speed * (0.6 + 0.8 * cel_hash11(cell.x * 7.3 + cell.y * 3.1))
		+ cel_hash11(cell.x * 11.5 + cell.y * 47.7)
	);
	float d = length(local - site);
	// Expanding ring that dies as it reaches the cell edge.
	float ring = smoothstep(0.05, 0.0, abs(d - phase * 0.45)) * (1.0 - phase);
	return ring;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wp = v_world_pos.xz;

	// Ripple-ring gradient by finite difference, plus a broad wind-sheared
	// micro ripple. Both only tilt the normal; the surface stays flat.
	float r0 = ripple_height(wp);
	float rx = ripple_height(wp + vec2(0.06, 0.0));
	float rz = ripple_height(wp + vec2(0.0, 0.06));
	vec2 ring_grad = vec2(rx - r0, rz - r0) / 0.06;

	float mx = cel_value_noise11(wp.x * micro_scale + wp.y * 1.7 + TIME * micro_speed) - 0.5;
	float mz = cel_value_noise11(wp.y * micro_scale - wp.x * 1.3 + TIME * micro_speed * 1.31) - 0.5;

	vec3 n = normalize(vec3(
		ring_grad.x * ripple_strength + mx * micro_strength,
		1.0,
		ring_grad.y * ripple_strength + mz * micro_strength
	));
	NORMAL = normalize(mix(NORMAL, n, 0.9));

	float fres = cel_fresnel(n, VIEW, fresnel_power);

	ALBEDO = mix(deep_color.rgb, sky_tint.rgb, fres);
	// Faint self-light at grazing angles: a puddle at night never reads black,
	// it reads as the sky lying on the street.
	EMISSION = sky_tint.rgb * fres * reflection_strength * 0.22;
	ROUGHNESS = 0.05;

	float shore = cel_value_noise11(wp.x * shore_noise_scale + wp.y * shore_noise_scale * 1.93)
		* 0.65 + cel_value_noise11(wp.x * shore_noise_scale * 2.7 - wp.y * shore_noise_scale * 2.1) * 0.35;
	ALPHA = smoothstep(
		shore_threshold - shore_softness, shore_threshold + shore_softness, shore
	);
}

void light() {
	vec3 n = normalize(NORMAL);
	vec3 l = normalize(LIGHT);

	// Thin banded diffuse — water barely diffuses, but the cel read wants a
	// whisper of the light colour on the lit side.
	float wrapped = cel_wrap_ndotl(n, l, 0.15);
	float banded = cel_band(wrapped, 2.0, 0.05);
	DIFFUSE_LIGHT += LIGHT_COLOR * ALBEDO * banded * ATTENUATION * 0.25;

	// The money term: a tight, hot toon glint for every sign and lamp, so
	// neon stretches across the puddle in hard-edged streaks.
	float spec = cel_spec(n, l, VIEW, 0.05, spec_threshold, spec_softness);
	SPECULAR_LIGHT += spec * spec_strength * LIGHT_COLOR * ATTENUATION;
}
