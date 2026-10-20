// Night sky: dithered gradient, moon glow, milky way dust, twinkling stars, aurora curtains.
shader_type canvas_item;
#include "res://shaders/title/common.gdshaderinc"
uniform vec2 size = vec2(688.0, 360.0);
uniform vec2 moon = vec2(476.0, 86.0);
uniform float horizon = 214.0;

vec3 grad(float y) {
	vec3 c0 = vec3(5., 6., 22.) / 255.; vec3 c1 = vec3(16., 20., 52.) / 255.; vec3 c2 = vec3(40., 28., 84.) / 255.;
	vec3 c3 = vec3(86., 50., 128.) / 255.; vec3 c4 = vec3(168., 64., 128.) / 255.;
	float t = y / horizon;
	if (t < 0.35) return mix(c0, c1, t / 0.35);
	if (t < 0.65) return mix(c1, c2, (t - 0.35) / 0.3);
	if (t < 0.88) return mix(c2, c3, (t - 0.65) / 0.23);
	return mix(c3, c4, clamp((t - 0.88) / 0.12, 0.0, 1.0));
}

void fragment() {
	vec2 px = floor(UV * size);
	vec3 col = grad(px.y);
	float d = length(px - moon);
	col += vec3(0.16, 0.2, 0.36) * pow(clamp(1.0 - d / 200.0, 0.0, 1.0), 2.2);
	col += vec3(0.25, 0.3, 0.45) * pow(clamp(1.0 - d / 60.0, 0.0, 1.0), 2.0);
	// milky way: a dusty diagonal band
	float band = px.y - (20.0 + px.x * 0.28);
	float mw = exp(-band * band / 1800.0) * fbm3(px * vec2(0.05, 0.08));
	mw *= smoothstep(0.25, 0.75, fbm3(px * 0.025 + 3.0));
	col += vec3(0.16, 0.1, 0.24) * mw;
	// aurora: curtains with vertical rays, mint at the hem fading to violet
	float ph = loop_phase * TAU_;
	float hem = 92.0 + 18.0 * sin(px.x * 0.011 + ph) + 14.0 * vnoise(vec2(px.x * 0.018 + 2.0 * cos(ph), 3.0 + 2.0 * sin(ph)));
	float above = hem - px.y;
	float curtain = above > 0.0 ? exp(-above / 34.0) : exp(above / 2.5);
	float rays = 0.45 + 0.55 * vnoise(vec2(px.x * 0.22 + 1.5 * sin(ph + px.x * 0.01), 0.5 * cos(ph)));
	float reach = smoothstep(40.0, 200.0, px.x) * (1.0 - smoothstep(420.0, 520.0, px.x));
	float a = curtain * rays * reach * 0.55;
	vec3 ac = mix(vec3(0.33, 0.9, 0.66), vec3(0.62, 0.36, 0.95), clamp(above / 50.0, 0.0, 1.0));
	col += ac * a * 0.6;
	// stars: one candidate per 5x5 cell
	vec2 cell = floor(px / 5.0);
	float h = hash12(cell);
	vec2 sp = cell * 5.0 + floor(vec2(hash12(cell + 11.0), hash12(cell + 23.0)) * 5.0);
	float dens = (1.0 - smoothstep(130.0, 205.0, px.y)) * smoothstep(30.0, 60.0, d) * (0.55 + mw * 2.5);
	if (h < 0.26 * dens) {
		vec2 o = abs(px - sp);
		float k = floor(hash12(cell + 5.0) * 3.0) + 1.0;
		float tw = (0.55 + 0.45 * sin(TAU_ * (loop_phase * k + hash12(cell + 9.0)))) * (0.35 + 0.65 * pow(hash12(cell + 13.0), 3.0));
		float big = step(0.93, hash12(cell + 2.0));
		float s = 0.0;
		if (o.x + o.y < 0.5) s = 1.0;
		else if (big > 0.5 && o.x + o.y < 1.5) s = 0.45 * tw;
		vec3 sc = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.86, 0.7), step(0.7, hash12(cell + 4.0)));
		col = mix(col, sc * (0.5 + 0.7 * tw), s * (0.4 + 0.6 * tw));
	}
	COLOR = vec4(s2l(posterize(col, px, 64.0)), 1.0);
}
