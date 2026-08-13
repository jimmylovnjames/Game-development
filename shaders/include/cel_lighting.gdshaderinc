// Shared helpers for the NeonWastes cel-shading stack.
//
// Include with:
//   #include "res://shaders/include/cel_lighting.gdshaderinc"

#ifndef NEONWASTES_CEL_LIGHTING_INC
#define NEONWASTES_CEL_LIGHTING_INC

// Quantise a 0..1 lighting term into `bands` steps. Only the edge of each step
// is softened, so the ramp keeps its printed-comic hardness without aliasing
// along the terminator.
float cel_band(float value, float bands, float softness) {
	float soft = max(softness, 0.0001);
	float scaled = clamp(value, 0.0, 1.0) * bands;
	float lower = floor(scaled);
	float f = scaled - lower;
	return (lower + smoothstep(0.5 - soft, 0.5 + soft, f)) / bands;
}

// Wrapped N·L. `wrap` of 0 is plain lambert; higher values push light around the
// terminator so unlit sides read as tinted shadow rather than dead black.
float cel_wrap_ndotl(vec3 n, vec3 l, float wrap) {
	return clamp((dot(n, l) + wrap) / (1.0 + wrap), 0.0, 1.0);
}

// View-facing falloff used for rim light and for the wet-edge highlight.
float cel_fresnel(vec3 n, vec3 v, float power) {
	return pow(1.0 - clamp(dot(normalize(n), normalize(v)), 0.0, 1.0), max(power, 0.001));
}

// Toon specular: a hard-edged blob rather than a physical lobe.
float cel_spec(vec3 n, vec3 l, vec3 v, float roughness, float threshold, float softness) {
	vec3 h = normalize(l + normalize(v));
	float ndh = clamp(dot(normalize(n), h), 0.0, 1.0);
	float exponent = exp2((1.0 - clamp(roughness, 0.0, 1.0)) * 11.0);
	float raw = pow(ndh, exponent);
	float soft = max(softness, 0.0001);
	return smoothstep(threshold - soft, threshold + soft, raw);
}

float cel_hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float cel_value_noise11(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(cel_hash11(i), cel_hash11(i + 1.0), f);
}

// 2D Hash function for procedural grid & noise generation
vec2 cel_hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// 2D Value noise
float cel_noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = dot(cel_hash22(i + vec2(0.0, 0.0)) - 0.5, f - vec2(0.0, 0.0));
	float b = dot(cel_hash22(i + vec2(1.0, 0.0)) - 0.5, f - vec2(1.0, 0.0));
	float c = dot(cel_hash22(i + vec2(0.0, 1.0)) - 0.5, f - vec2(0.0, 1.0));
	float d = dot(cel_hash22(i + vec2(1.0, 1.0)) - 0.5, f - vec2(1.0, 1.0));
	return 0.5 + 0.5 * mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Comic Halftone dot raster pattern (screen-space or world-space)
float cel_halftone(vec2 coord, float scale, float darkness) {
	vec2 grid = fract(coord * scale) - 0.5;
	float dist = length(grid);
	float dot_radius = clamp(darkness, 0.0, 1.0) * 0.55;
	return 1.0 - smoothstep(dot_radius - 0.05, dot_radius + 0.05, dist);
}

// Comic ink cross-hatch pattern for deep shadows
float cel_hatching(vec2 coord, float scale, float darkness) {
	vec2 rot_coord1 = vec2(coord.x + coord.y, coord.y - coord.x) * 0.7071 * scale;
	vec2 rot_coord2 = vec2(coord.x - coord.y, coord.x + coord.y) * 0.7071 * scale;
	
	float line1 = abs(fract(rot_coord1.x) - 0.5) * 2.0;
	float line2 = abs(fract(rot_coord2.x) - 0.5) * 2.0;
	
	float hatch1 = smoothstep(1.0 - darkness * 1.5, 1.0, 1.0 - line1);
	float hatch2 = smoothstep(1.0 - (darkness - 0.4) * 2.0, 1.0, 1.0 - line2);
	
	return clamp(hatch1 + hatch2, 0.0, 1.0);
}

#endif // NEONWASTES_CEL_LIGHTING_INC
