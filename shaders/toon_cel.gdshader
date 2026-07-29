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

varying float v_fresnel;
varying vec3 v_world_normal;

void vertex() {
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 tex = texture(albedo_texture, uv);
	vec3 base = albedo_color.rgb * tex.rgb;

	float grime = texture(grime_texture, uv).r * grime_strength;
	grime *= mix(1.0, clamp(v_world_normal.y, 0.0, 1.0), grime_up_bias);
	base = mix(base, grime_color.rgb, grime);

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
	float banded = cel_band(wrapped, light_bands, band_softness);
	float shaded = banded * ATTENUATION;

	vec3 lit = LIGHT_COLOR * ALBEDO * shaded;

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
