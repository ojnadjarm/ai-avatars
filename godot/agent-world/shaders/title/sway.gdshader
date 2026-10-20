// Wind sway: pixel-stepped horizontal shift from a weight (R) + phase (G) map, so each cluster or blade moves on its own.
shader_type canvas_item;
#include "res://shaders/title/common.gdshaderinc"
uniform sampler2D wmap : filter_nearest;
uniform vec2 size = vec2(688.0, 360.0);
uniform float amp = 1.5;
uniform float freq = 2.0;
uniform vec3 dark = vec3(0.5, 0.5, 0.6);
uniform vec3 moon_dir = vec3(0.55, 0.45, 0.7);
uniform vec3 moon_col = vec3(0.16, 0.2, 0.42);

void fragment() {
	vec2 px = floor(UV * size);
	vec4 w = texture(wmap, (px + 0.5) / size);
	float ph = loop_phase * TAU_ * freq + w.g * TAU_;
	float s = round(amp * w.r * (sin(ph) + 0.4 * sin(ph * 2.0 + 1.3)));
	vec4 c = texture(TEXTURE, (px + vec2(-s, 0.0) + 0.5) / size);
	COLOR = vec4(c.rgb * dark + c.rgb * moon_col * max(dot(NORMAL, normalize(moon_dir)) - 0.55, 0.0) * 2.2, c.a);
}
void light() {
	vec3 a = texture(TEXTURE, UV).rgb;
	float nl = clamp(dot(NORMAL, LIGHT_DIRECTION) * 0.7 + 0.3, 0.0, 1.0);
	LIGHT = vec4(a * LIGHT_COLOR.rgb * LIGHT_ENERGY * nl, LIGHT_COLOR.a);
}
