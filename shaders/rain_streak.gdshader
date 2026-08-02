shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// A single rain streak: a thin stretched prism with soft alpha edges. Drawn by
// the thousands through GPUParticles3D, so this shader does as little as
// possible — the motion blur illusion comes from the stretch, not the shader.
// COLOR carries the particle's lifetime fade from the process material.

uniform vec4 streak_color : source_color = vec4(0.45, 0.55, 0.75, 0.32);
uniform float tip_fade : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	// Soften the silhouette along both UV axes; on the thin side faces of the
	// prism this kills the hard edge that would otherwise alias in sheets.
	float edge = 1.0 - abs(UV.x - 0.5) * 2.0;
	float tail = mix(1.0, smoothstep(0.0, 0.35, UV.y), tip_fade);
	ALBEDO = streak_color.rgb;
	ALPHA = streak_color.a * edge * tail * COLOR.a;
}
