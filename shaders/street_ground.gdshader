shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Wet asphalt for the district ground plane. Textures in world XZ so the
// 500 m plane does not stretch a single UV tile across the whole city, and so
// the same material can sit under procedurally placed sidewalks without seams.
//
// Comic discipline still applies: 2 light bands, soft specular (this is a
// giant flat plane — hard toon specular becomes a spotlight-sized disc), and
// saturated colour only from light, never from paint.

#include "res://shaders/include/cel_lighting.gdshaderinc"

group_uniforms Surface;
uniform vec4 asphalt_color : source_color = vec4(0.075, 0.07, 0.095, 1.0);
uniform vec4 patch_color : source_color = vec4(0.11, 0.09, 0.08, 1.0);
uniform vec4 crack_color : source_color = vec4(0.03, 0.025, 0.04, 1.0);
uniform vec4 oil_color : source_color = vec4(0.04, 0.05, 0.07, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.28;

group_uniforms Detail;
uniform float asphalt_scale : hint_range(0.02, 2.0) = 0.22;
uniform float patch_scale : hint_range(0.01, 1.0) = 0.05;
uniform float crack_scale : hint_range(0.05, 4.0) = 0.28;
uniform float crack_width : hint_range(0.01, 0.4) = 0.045;
uniform float oil_scale : hint_range(0.01, 1.0) = 0.06;
uniform float oil_amount : hint_range(0.0, 1.0) = 0.22;
uniform float wetness : hint_range(0.0, 1.0) = 0.55;

group_uniforms Markings;
// Lane dashes sit on the street lattice the blockout also uses.
uniform float street_stride : hint_range(1.0, 80.0) = 31.0;
uniform float dash_half_width : hint_range(0.02, 0.5) = 0.08;
uniform float dash_length : hint_range(0.2, 4.0) = 1.4;
uniform float dash_gap : hint_range(0.2, 6.0) = 2.2;
uniform vec4 paint_color : source_color = vec4(0.55, 0.52, 0.42, 1.0);
uniform float paint_strength : hint_range(0.0, 1.0) = 0.4;

group_uniforms Cel;
uniform float light_bands : hint_range(1.0, 6.0, 1.0) = 2.0;
uniform float band_softness : hint_range(0.001, 0.25) = 0.06;
uniform float shadow_wrap : hint_range(0.0, 1.0) = 0.45;
uniform vec4 shadow_tint : source_color = vec4(0.16, 0.1, 0.34, 1.0);
uniform float shadow_tint_strength : hint_range(0.0, 1.0) = 0.45;

group_uniforms Specular;
uniform float spec_threshold : hint_range(0.0, 1.0) = 0.35;
uniform float spec_softness : hint_range(0.001, 0.5) = 0.4;
uniform float spec_strength : hint_range(0.0, 4.0) = 0.4;

group_uniforms Rim;
uniform vec4 rim_color : source_color = vec4(1.0, 0.18, 0.58, 1.0);
uniform float rim_power : hint_range(0.5, 12.0) = 6.0;
uniform float rim_strength : hint_range(0.0, 4.0) = 0.28;
uniform float rim_light_bias : hint_range(0.0, 1.0) = 0.85;

varying float v_fresnel;
varying vec3 v_world_pos;
varying float v_local_rough;

float street_hash(vec2 p) {
	return cel_hash11(p.x * 12.9898 + p.y * 78.233);
}

float street_value(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = street_hash(i);
	float b = street_hash(i + vec2(1.0, 0.0));
	float c = street_hash(i + vec2(0.0, 1.0));
	float d = street_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float street_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * street_value(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

// Thin dark veins: take the distance to the nearest Voronoi edge.
float crack_field(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	float min_d = 10.0;
	float second = 10.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbour = vec2(float(x), float(y));
			vec2 point = neighbour + vec2(
				street_hash(cell + neighbour),
				street_hash(cell + neighbour + vec2(19.1, 3.7))
			);
			float d = length(local - point);
			if (d < min_d) {
				second = min_d;
				min_d = d;
			} else if (d < second) {
				second = d;
			}
		}
	}
	return second - min_d;
}

float lane_paint(vec2 wp) {
	// Cross of dashed lines at every street centreline. Street centres sit
	// halfway between lot centres (stride away from each other).
	float half = street_stride * 0.5;
	float along_x = abs(mod(wp.x + half, street_stride) - half);
	float along_z = abs(mod(wp.y + half, street_stride) - half);

	float dash_period = dash_length + dash_gap;
	float dash_x = step(mod(wp.y + dash_length * 0.5, dash_period), dash_length);
	float dash_z = step(mod(wp.x + dash_length * 0.5, dash_period), dash_length);

	float line_x = (1.0 - smoothstep(dash_half_width, dash_half_width + 0.04, along_x)) * dash_x;
	float line_z = (1.0 - smoothstep(dash_half_width, dash_half_width + 0.04, along_z)) * dash_z;
	// Kill paint near junctions so the dashes do not pile into a white blot.
	float junction = step(2.4, max(along_x, along_z));
	return max(line_x, line_z) * junction;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wp = v_world_pos.xz;

	float grain = street_fbm(wp * asphalt_scale);
	float patches = smoothstep(0.62, 0.88, street_fbm(wp * patch_scale + 3.1));
	// Thin dark veins only — wide crack_width turns the Voronoi cells into a
	// glowing honeycomb under wet specular, which fights the comic read.
	float cracks = 1.0 - smoothstep(0.0, crack_width, crack_field(wp * crack_scale));
	cracks = pow(cracks, 2.5);
	float oil = smoothstep(0.72, 0.95, street_fbm(wp * oil_scale + 11.7)) * oil_amount;

	vec3 base = mix(asphalt_color.rgb, patch_color.rgb, patches * 0.35);
	base *= 0.82 + grain * 0.28;
	base = mix(base, crack_color.rgb, cracks * 0.7);
	base = mix(base, oil_color.rgb, oil);

	float paint = lane_paint(wp) * paint_strength;
	base = mix(base, paint_color.rgb, paint);

	// Oil and paint stay wetter; cracks drink the water and go matte.
	float local_wet = clamp(wetness + oil * 0.35 - cracks * 0.4 + paint * 0.15, 0.0, 1.0);
	v_local_rough = mix(0.72, roughness * 0.55, local_wet);

	ALBEDO = base;
	ROUGHNESS = v_local_rough;
	METALLIC = oil * 0.25;

	v_fresnel = cel_fresnel(NORMAL, VIEW, rim_power);
	EMISSION = rim_color.rgb * v_fresnel * rim_strength * (1.0 - rim_light_bias);
}

void light() {
	vec3 n = normalize(NORMAL);
	vec3 l = normalize(LIGHT);

	float wrapped = cel_wrap_ndotl(n, l, shadow_wrap);
	float banded = cel_band(wrapped, light_bands, band_softness);
	float shaded = banded * ATTENUATION;

	vec3 lit = LIGHT_COLOR * ALBEDO * shaded;
	vec3 shade = shadow_tint.rgb * ALBEDO * LIGHT_COLOR
		* (1.0 - banded) * ATTENUATION * shadow_tint_strength;

	float rim = v_fresnel * rim_strength * rim_light_bias
		* clamp(dot(n, l) * 0.5 + 0.5, 0.0, 1.0) * ATTENUATION;

	DIFFUSE_LIGHT += lit + shade + rim_color.rgb * rim * LIGHT_COLOR;

	float spec = cel_spec(n, l, VIEW, ROUGHNESS, spec_threshold, spec_softness);
	// Wetness boosts the soft specular so neon actually stretches on the street.
	float wet_boost = mix(0.45, 1.1, 1.0 - ROUGHNESS);
	SPECULAR_LIGHT += spec * spec_strength * wet_boost * LIGHT_COLOR * ATTENUATION;
}
