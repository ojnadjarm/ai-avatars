// Pixel mist band: drifting fbm, dithered alpha, tinted.
shader_type canvas_item;
#include "res://shaders/title/common.gdshaderinc"
uniform vec2 size = vec2(688.0, 60.0);
uniform vec4 tint : source_color = vec4(0.6, 0.5, 0.9, 1.0);
uniform float strength = 0.6;
uniform vec2 scale = vec2(0.03, 0.12);
uniform vec2 drift = vec2(1.2, 0.0);
uniform float seed = 0.0;

void fragment() {
	vec2 px = floor(UV * size);
	float n = drift_fbm(px * scale + seed, drift);
	float prof = sin(clamp(UV.y, 0.0, 1.0) * 3.14159);
	float a = clamp((n - 0.35) * 2.2, 0.0, 1.0) * prof * strength;
	a = floor(a * 6.0 + bayer4(px)) / 6.0;
	COLOR = vec4(s2l(tint.rgb), a);
}
