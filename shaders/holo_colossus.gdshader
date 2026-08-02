shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// AD-7, the ad that watches. A building-scale hologram face: two glowing eyes
// with a slow gaze drift and an occasional blink, a thin contemptuous mouth,
// all drawn procedurally so no texture memory goes to a one-off landmark.
// Scanlines and glitch beats keep it in the same failing-hardware family as
// the street holo boards.

#include "res://shaders/include/cel_lighting.gdshaderinc"

group_uniforms Holo;
uniform vec4 holo_color : source_color = vec4(0.0, 0.898, 1.0, 1.0);
uniform vec4 accent_color : source_color = vec4(1.0, 0.176, 0.584, 1.0);
uniform float energy : hint_range(0.0, 8.0) = 2.0;
uniform float phase_offset : hint_range(0.0, 100.0) = 0.0;

group_uniforms Face;
// Where the eyes sit and how far they roam.
uniform vec2 eye_spacing = vec2(0.19, 0.14);
uniform float eye_radius : hint_range(0.01, 0.2) = 0.062;
uniform float gaze_speed : hint_range(0.0, 1.0) = 0.08;
uniform float blink_seconds : hint_range(0.05, 0.6) = 0.16;
// Mouth curvature: positive smirks, negative scowls.
uniform float mouth_curve : hint_range(-0.1, 0.1) = 0.035;

group_uniforms Scanlines;
uniform float scanline_density : hint_range(8.0, 200.0) = 64.0;
uniform float scanline_speed : hint_range(-4.0, 4.0) = 0.4;

group_uniforms Glitch;
uniform float glitch_rate : hint_range(0.0, 30.0) = 2.5;
uniform float glitch_chance : hint_range(0.0, 1.0) = 0.16;
uniform float glitch_strength : hint_range(0.0, 0.5) = 0.05;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	float t = TIME + phase_offset;

	vec2 uv = v_uv;
	// Glitch strip shear, shared language with the street boards.
	float slot = floor(t * glitch_rate);
	if (cel_hash11(slot * 0.731) < glitch_chance) {
		float strip = floor(uv.y * 32.0);
		float shear = cel_hash11(slot + strip * 13.7) - 0.5;
		uv.x += shear * glitch_strength * step(0.6, cel_hash11(strip * 3.3 + slot));
	}

	vec2 p = (uv - 0.5) * 2.0; // -1..1 face space, y up when quad is upright

	// Gaze: slow drunk wander, same for both eyes.
	vec2 gaze = vec2(
		cel_value_noise11(t * gaze_speed * 3.1) - 0.5,
		cel_value_noise11(t * gaze_speed * 2.3 + 40.0) - 0.5
	) * 0.16;

	// Blink: a slot every ~4-7 s squishes the eye ellipse vertically.
	float blink_slot = floor(t / (3.0 + 4.0 * cel_hash11(floor(t * 0.21))));
	float blink_phase = fract(t * 0.21);
	float blink = 1.0;
	if (blink_phase < blink_seconds) {
		blink = abs(blink_phase / blink_seconds * 2.0 - 1.0);
		blink = 0.12 + 0.88 * blink;
	}

	float face = 0.0;
	for (int side = 0; side < 2; side++) {
		float sx = side == 0 ? -eye_spacing.x : eye_spacing.x;
		vec2 eye_c = vec2(sx, eye_spacing.y) + gaze;
		vec2 d = p - eye_c;
		d.y /= max(blink, 0.05);
		float eye = 1.0 - smoothstep(eye_radius * 0.6, eye_radius, length(d));
		// Hot core with a darker pupil so the gaze reads as a gaze.
		vec2 pd = p - (eye_c + gaze * 0.6);
		pd.y /= max(blink, 0.05);
		float pupil = smoothstep(eye_radius * 0.28, eye_radius * 0.45, length(pd));
		face += eye * mix(0.35, 1.0, pupil);
	}

	// Mouth: a shallow arc whose curvature is set by mouth_curve.
	float mouth_y = -0.24 + mouth_curve * (p.x * p.x * 6.0 - 1.0);
	float mouth = (1.0 - smoothstep(0.012, 0.035, abs(p.y - mouth_y)))
		* step(abs(p.x), 0.24);
	face += mouth * 0.8;

	// Faint face-plate contour so the head reads as a head.
	float contour = abs(length(p * vec2(0.82, 1.0)) - 0.78);
	face += (1.0 - smoothstep(0.004, 0.03, contour)) * 0.35;

	float scan = sin((uv.y * scanline_density - t * scanline_speed) * 6.28318);
	float lines = mix(1.0, 0.35, smoothstep(-0.4, 0.4, scan));
	float flicker = 1.0 - 0.12 * cel_value_noise11(t * 7.0);

	vec3 col = mix(holo_color.rgb, accent_color.rgb, smoothstep(-0.2, 0.5, p.y));
	ALBEDO = col * energy * face * lines * flicker;
	ALPHA = 1.0;
}
