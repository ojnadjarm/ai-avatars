// Campfire: pixel flame from rising drifting noise, fire ramp, HDR core for the glow.
shader_type canvas_item;
#include "res://shaders/title/common.gdshaderinc"
uniform vec2 size = vec2(16.0, 26.0);
void fragment() {
	vec2 px = floor(UV * size);
	float y = 1.0 - (px.y + 0.5) / size.y;
	float x = (px.x + 0.5) / size.x - 0.5;
	float n = drift_fbm(vec2(px.x * 0.28, px.y * 0.16), vec2(0.0, -6.0));
	float wid = 0.42 * (1.0 - y) * (0.7 + 0.5 * n);
	float sway = 0.06 * sin(loop_phase * TAU_ * 9.0 + y * 4.0) * y;
	float f = clamp(1.0 - abs(x - sway) / max(wid, 0.001), 0.0, 1.0) * clamp((1.0 - y) * 1.6 - (1.0 - n) * 0.7, 0.0, 1.0);
	f = f * 1.6;
	vec3 c = vec3(0.0);
	float a = 0.0;
	if (f > 0.05) { c = vec3(0.75, 0.2, 0.08) * 2.0; a = 1.0; }
	if (f > 0.35) c = vec3(1.0, 0.54, 0.23) * 2.6;
	if (f > 0.7) c = vec3(0.95, 0.77, 0.35) * 3.2;
	if (f > 1.05) c = vec3(1.0, 0.95, 0.7) * 4.0;
	COLOR = vec4(c, a);
}
