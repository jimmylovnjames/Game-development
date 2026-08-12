shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// NeonWastes workhorse surface shader.
//
// Banded diffuse + hard toon specular + fresnel rim, with the unlit half of
// every surface tinted toward cold violet instead of crushing to black. That
// tint is what keeps the wasteland reading as noir rather than as an unlit bug.
//
// Pair with res://assets/materials/outline_ink.tres as `next_pass` to get the
// inked silhouette. See docs/style_bible.md for the palette this is tuned to.

#include "res://shaders/include/cel_lighting.gdshaderinc"

group_uniforms Surface;
uniform vec4 albedo_color : source_color = vec4(0.55, 0.56, 0.62, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.78;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

group_uniforms Cel;
// 2-3 bands is the comic look. 4+ drifts toward conventional smooth shading.
uniform float light_bands : hint_range(1.0, 6.0, 1.0) = 3.0;
uniform float band_softness : hint_range(0.001, 0.25) = 0.03;
uniform float shadow_wrap : hint_range(0.0, 1.0) = 0.35;
uniform vec4 shadow_tint : source_color = vec4(0.24, 0.18, 0.42, 1.0);
uniform float shadow_tint_strength : hint_range(0.0, 1.0) = 0.5;

group_uniforms Ramp;
// Optional 1D light ramp sampled by the wrapped N-dot-L, replacing the analytic
// banding. A ramp is authorable — an artist sets where the steps fall and what
// colour each band is — and it can carry a hue shift across the terminator
// (cold violet shadow into a warm key) that a numeric band count cannot express
// at all. See assets/materials/ramps/.
uniform sampler2D light_ramp : source_color, filter_linear, hint_default_white;
uniform bool use_light_ramp = false;

group_uniforms Specular;
uniform float spec_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float spec_softness : hint_range(0.001, 0.3) = 0.02;
uniform float spec_strength : hint_range(0.0, 4.0) = 0.8;

group_uniforms Rim;
uniform vec4 rim_color : source_color = vec4(0.0, 0.9, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 12.0) = 3.5;
uniform float rim_strength : hint_range(0.0, 4.0) = 0.9;
// 0 = rim always on (readable in the dark), 1 = rim only where lights hit.
uniform float rim_light_bias : hint_range(0.0, 1.0) = 0.55;

group_uniforms Emission;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;

group_uniforms Grime;
// Rust/soot overlay so untextured blockout geometry still reads as post-apoc.
uniform sampler2D grime_texture : filter_linear_mipmap, hint_default_white;
uniform vec4 grime_color : source_color = vec4(0.22, 0.11, 0.07, 1.0);
uniform float grime_strength : hint_range(0.0, 1.0) = 0.0;
// Grime pools downward: 1.0 restricts it to upward-facing surfaces.
uniform float grime_up_bias : hint_range(0.0, 1.0) = 0.0;

group_uniforms Detail;
// Soft tonal flecks for skin and fabric. Reads as ink-wash variation, not
// photographic noise — keep strength low so banding still owns the look.
uniform float detail_strength : hint_range(0.0, 0.4) = 0.0;
uniform float detail_scale : hint_range(0.5, 48.0) = 10.0;
uniform float detail_contrast : hint_range(0.0, 1.0) = 0.55;

varying float v_fresnel;
varying vec3 v_world_normal;
varying vec3 v_world_pos;

void vertex() {
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 tex = texture(albedo_texture, uv);
	vec3 base = albedo_color.rgb * tex.rgb;

	float grime = texture(grime_texture, uv).r * grime_strength;
	grime *= mix(1.0, clamp(v_world_normal.y, 0.0, 1.0), grime_up_bias);
	base = mix(base, grime_color.rgb, grime);

	if (detail_strength > 0.001) {
		float n1 = cel_value_noise11(
			v_world_pos.x * detail_scale + v_world_pos.z * detail_scale * 0.73
		);
		float n2 = cel_value_noise11(
			v_world_pos.y * detail_scale * 1.31 - v_world_pos.x * detail_scale * 0.41
		);
		float fleck = mix(n1, n2, 0.45);
		fleck = mix(0.5, fleck, detail_contrast);
		base *= mix(1.0, 0.74 + fleck * 0.52, detail_strength);
	}

	ALBEDO = base;
	ALPHA = albedo_color.a * tex.a;
	ROUGHNESS = roughness;
	METALLIC = metallic;

	v_fresnel = cel_fresnel(NORMAL, VIEW, rim_power);

	// The light-independent share of the rim goes through EMISSION so silhouettes
	// stay legible in pitch-dark alleys where no light() pass ever runs.
	EMISSION = emission_color.rgb * emission_energy
		+ rim_color.rgb * v_fresnel * rim_strength * (1.0 - rim_light_bias);
}

void light() {
	vec3 n = normalize(NORMAL);
	vec3 l = normalize(LIGHT);

	float wrapped = cel_wrap_ndotl(n, l, shadow_wrap);

	float banded;
	vec3 ramp_tint = vec3(1.0);
	if (use_light_ramp) {
		// Clamp off the very edges: a linear-filtered 1D texture bleeds the
		// clamp colour into the first and last texel otherwise, which shows up
		// as a thin wrong-coloured rim exactly on the terminator.
		vec3 ramp = texture(light_ramp, vec2(clamp(wrapped, 0.01, 0.99), 0.5)).rgb;
		// Split the ramp into brightness (drives the band) and hue (tints the
		// lit term), so one texture carries both the steps and the colour.
		banded = max(max(ramp.r, ramp.g), ramp.b);
		ramp_tint = banded > 0.0001 ? ramp / banded : vec3(1.0);
	} else {
		banded = cel_band(wrapped, light_bands, band_softness);
	}
	float shaded = banded * ATTENUATION;

	vec3 lit = LIGHT_COLOR * ALBEDO * ramp_tint * shaded;

	// Tint the unlit facing toward this light's colour rather than adding a flat
	// ambient term, so a magenta sign throws magenta shadow and a cyan one cyan.
	//
	// The un-lit fraction is (1.0 - banded), i.e. angle only. ATTENUATION has to
	// be applied on top: fold it into the fraction instead and a distant light
	// (ATTENUATION -> 0) contributes its tint at *full* strength, so every light
	// in the level washes every surface. Distance must kill this term.
	vec3 shade = shadow_tint.rgb * ALBEDO * LIGHT_COLOR
		* (1.0 - banded) * ATTENUATION * shadow_tint_strength;

	// Rim brightens on lit facings when rim_light_bias is high.
	float rim = v_fresnel * rim_strength * rim_light_bias
		* clamp(dot(n, l) * 0.5 + 0.5, 0.0, 1.0) * ATTENUATION;

	DIFFUSE_LIGHT += lit + shade + rim_color.rgb * rim * LIGHT_COLOR;

	float spec = cel_spec(n, l, VIEW, ROUGHNESS, spec_threshold, spec_softness);
	SPECULAR_LIGHT += spec * spec_strength * LIGHT_COLOR * ATTENUATION;
}
