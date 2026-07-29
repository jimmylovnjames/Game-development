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

#endif // NEONWASTES_CEL_LIGHTING_INC
