shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque, shadows_disabled;

// Inverted-hull ink outline. Intended as the `next_pass` of a toon_cel material.
//
// The hull is pushed along the vertex normal and rendered back-faces-only, which
// leaves a constant band of ink around every silhouette. Meshes with split
// (hard-edged) normals tear at the seams — either author smooth normals for
// outlined props, or fall back to the screen-space alternative described in
// docs/style_bible.md.

uniform vec4 outline_color : source_color = vec4(0.03, 0.02, 0.06, 1.0);
uniform float outline_width : hint_range(0.0, 0.05) = 0.004;
// Scale the hull by view depth so distant buildings keep the same ink weight on
// screen instead of thinning out to nothing.
uniform bool constant_screen_width = true;
uniform float max_scale_distance : hint_range(1.0, 500.0) = 140.0;
// Fade the ink out past the fog line; a hard outline on a fogged shape looks cut out.
uniform float fade_start : hint_range(0.0, 500.0) = 90.0;
uniform float fade_end : hint_range(0.0, 800.0) = 180.0;

varying float v_view_depth;

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float depth = max(-view_pos.z, 0.001);
	v_view_depth = depth;

	float width = outline_width;
	if (constant_screen_width) {
		width *= clamp(depth, 0.1, max_scale_distance);
	}

	vec3 n = NORMAL;
	// Guard against degenerate normals on procedurally generated geometry.
	if (dot(n, n) < 0.0001) {
		n = vec3(0.0, 1.0, 0.0);
	}
	VERTEX += normalize(n) * width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a * (1.0 - smoothstep(fade_start, max(fade_end, fade_start + 0.001), v_view_depth));
}
