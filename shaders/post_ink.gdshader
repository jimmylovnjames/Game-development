shader_type canvas_item;

// Screen-space comic ink. Reads luminance edges on the rendered frame and lays
// near-black plum along high-contrast boundaries — silhouettes against lit
// ground and sky, sign housings against tubes, kerbs against wet asphalt. A
// four-tap blur per side keeps 24 fps grain from inking itself.
//
// canvas_item post passes in 4.7 cannot read the depth texture, so this is a
// luminance Sobel rather than a geometric edge pass. In a scene this
// high-contrast the two mostly agree.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

group_uniforms Ink;
uniform vec4 ink_color : source_color = vec4(0.03, 0.02, 0.06, 1.0);
uniform float ink_strength : hint_range(0.0, 1.0) = 0.75;
uniform float edge_threshold : hint_range(0.01, 1.0) = 0.18;
uniform float line_thickness : hint_range(0.5, 4.0) = 1.0;
// Ink weakens on very bright frames: neon bloom is allowed to bleed over ink.
uniform float bright_cut : hint_range(0.5, 4.0) = 1.6;

float lum_at(vec2 uv, vec2 px) {
	vec3 acc = vec3(0.0);
	acc += texture(screen_texture, uv + vec2(px.x, 0.0)).rgb;
	acc += texture(screen_texture, uv - vec2(px.x, 0.0)).rgb;
	acc += texture(screen_texture, uv + vec2(0.0, px.y)).rgb;
	acc += texture(screen_texture, uv - vec2(0.0, px.y)).rgb;
	vec3 avg = acc * 0.25;
	return dot(avg, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 px = 1.0 / vec2(textureSize(screen_texture, 0));
	vec2 t = px * line_thickness * 2.0;

	float gx = lum_at(SCREEN_UV + vec2(t.x, 0.0), px) - lum_at(SCREEN_UV - vec2(t.x, 0.0), px);
	float gy = lum_at(SCREEN_UV + vec2(0.0, t.y), px) - lum_at(SCREEN_UV - vec2(0.0, t.y), px);
	float diag = lum_at(SCREEN_UV + t, px) - lum_at(SCREEN_UV - t, px);
	float edge = abs(gx) + abs(gy) + abs(diag) * 0.7;

	vec3 col = texture(screen_texture, SCREEN_UV).rgb;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));

	float ink = smoothstep(edge_threshold, edge_threshold * 2.2, edge);
	ink *= 1.0 - smoothstep(bright_cut * 0.7, bright_cut, lum);
	col = mix(col, ink_color.rgb, ink * ink_strength);
	COLOR = vec4(col, 1.0);
}
