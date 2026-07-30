shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Ground impact ring for the rain system: a flat quad with a soft annulus of
// alpha. The particle system scales the quad up and fades COLOR.a over the
// particle's short life; this shader just draws the ring shape.

uniform vec4 splash_color : source_color = vec4(0.5, 0.62, 0.8, 0.4);
uniform float ring_radius : hint_range(0.1, 0.9) = 0.68;
uniform float ring_width : hint_range(0.02, 0.5) = 0.18;

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float ring = smoothstep(ring_width, 0.0, abs(d - ring_radius));
	// A faint disc inside the ring reads as the crown of the splash.
	float core = smoothstep(0.45, 0.0, d) * 0.25;
	ALBEDO = splash_color.rgb;
	ALPHA = splash_color.a * (ring + core) * COLOR.a;
}
