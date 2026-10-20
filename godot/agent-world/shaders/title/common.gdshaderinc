// Shared helpers: loop phase, hash, value noise, Bayer dither, base-pixel snapping.
global uniform float loop_phase;
const float TAU_ = 6.28318530718;
float hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}
float fbm3(vec2 p) { return vnoise(p) * 0.55 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.1 + 3.3) * 0.15; }
float bayer4(vec2 px) {
	int x = int(mod(px.x, 4.0)); int y = int(mod(px.y, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}
// Noise that drifts by `dir` per loop and still loops seamlessly (two-phase crossfade).
float drift_fbm(vec2 p, vec2 dir) {
	float a = fract(loop_phase); float b = fract(loop_phase + 0.5);
	float n1 = fbm3(p - dir * a); float n2 = fbm3(p - dir * b + vec2(17.3, 5.1));
	return mix(n1, n2, abs(2.0 * a - 1.0));
}
vec3 posterize(vec3 c, vec2 px, float levels) { return floor(c * levels + bayer4(px)) / levels; }
vec3 s2l(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }
