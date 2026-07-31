shader_type sky;

// Ferrum Halo night sky: near-black zenith, neon haze at the horizon, slow
// cloud deck, and heat lightning that flashes the deck from the direction of
// the arcology. Pairs with scripts/world/storm_director.gd, which spikes the
// key light on the same beat rhythm.

uniform vec4 zenith_color : source_color = vec4(0.035, 0.026, 0.08, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.31, 0.067, 0.376, 1.0);
uniform vec4 ground_color : source_color = vec4(0.02, 0.016, 0.03, 1.0);

group_uniforms NeonGlow;
uniform vec4 glow_a_color : source_color = vec4(1.0, 0.176, 0.584, 1.0);
uniform vec3 glow_a_dir = vec3(0.55, 0.0, -0.8);
uniform vec4 glow_b_color : source_color = vec4(0.0, 0.898, 1.0, 1.0);
uniform vec3 glow_b_dir = vec3(-0.7, 0.0, 0.5);
uniform float glow_strength : hint_range(0.0, 2.0) = 0.5;

group_uniforms Clouds;
uniform vec4 cloud_color : source_color = vec4(0.12, 0.08, 0.2, 1.0);
uniform float cloud_scale : hint_range(0.1, 8.0) = 1.4;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_speed : hint_range(0.0, 0.2) = 0.01;

group_uniforms Lightning;
// Per ~7.7 s slot, probability the deck flashes.
uniform float lightning_chance : hint_range(0.0, 1.0) = 0.16;
uniform float lightning_strength : hint_range(0.0, 4.0) = 1.1;

float sky_hash(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float sky_value(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = sky_hash(i.x * 12.9898 + i.y * 78.233);
	float b = sky_hash((i.x + 1.0) * 12.9898 + i.y * 78.233);
	float c = sky_hash(i.x * 12.9898 + (i.y + 1.0) * 78.233);
	float d = sky_hash((i.x + 1.0) * 12.9898 + (i.y + 1.0) * 78.233);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float sky_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * sky_value(p);
		p = p * 2.11 + vec2(13.7, 7.3);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = clamp(dir.y, 0.0, 1.0);

	vec3 col = mix(horizon_color.rgb, zenith_color.rgb, pow(up, 0.55));
	if (dir.y < 0.0) {
		col = mix(horizon_color.rgb * 0.5, ground_color.rgb, clamp(-dir.y * 5.0, 0.0, 1.0));
	}

	// Neon bounce off the cloud deck, one lobe per city district.
	float horizon_band = 1.0 - smoothstep(0.0, 0.3, abs(dir.y));
	vec2 flat_dir = normalize(dir.xz + vec2(0.0001, 0.0));
	float ga = pow(max(dot(flat_dir, normalize(glow_a_dir.xz)), 0.0), 5.0);
	float gb = pow(max(dot(flat_dir, normalize(glow_b_dir.xz)), 0.0), 5.0);
	col += (glow_a_color.rgb * ga + glow_b_color.rgb * gb) * horizon_band * glow_strength;

	if (dir.y > 0.015) {
		vec2 p = dir.xz / (dir.y + 0.15) * cloud_scale
			+ vec2(TIME * cloud_speed * 9.0, TIME * cloud_speed * 3.0);
		float cover = sky_fbm(p);
		float clouds = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.3, cover)
			* smoothstep(0.02, 0.22, dir.y);
		col = mix(col, cloud_color.rgb, clouds * 0.85);

		// Heat lightning inside the deck, biased toward the arcology lobe.
		float slot = floor(TIME * 0.13);
		float roll = sky_hash(slot * 0.717);
		if (roll < lightning_chance) {
			float phase = fract(TIME * 0.13);
			float flicker = 0.55 + 0.45 * sky_hash(slot * 7.31 + floor(phase * 26.0));
			float envelope = pow(1.0 - phase, 1.8) * flicker;
			col += (clouds * 1.6 + 0.25) * envelope * lightning_strength
				* mix(glow_b_color.rgb, vec3(0.9, 0.95, 1.0), 0.6) * (0.4 + 0.6 * gb);
		}
	}

	COLOR = col;
}
