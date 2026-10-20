// Moon god rays: angular noise fan, distance falloff, dithered additive.
shader_type canvas_item;
render_mode blend_add;
#include "res://shaders/title/common.gdshaderinc"
uniform vec2 size = vec2(688.0, 360.0);
uniform vec2 moon = vec2(476.0, 86.0);
uniform float strength = 0.34;

void fragment() {
	vec2 px = floor(UV * size);
	vec2 d = px - moon;
	float r = length(d);
	float ang = atan(d.y, d.x);
	float ph = loop_phase * TAU_;
	float n = vnoise(vec2(ang * 18.0 + 0.6 * sin(ph), 1.0 + 0.6 * cos(ph))) * vnoise(vec2(ang * 7.0 - 0.4 * sin(ph), 4.0));
	float fan = smoothstep(0.2, 0.9, ang) * (1.0 - smoothstep(2.4, 3.0, ang));
	float fall = smoothstep(26.0, 60.0, r) * exp(-r / 260.0);
	float a = pow(n, 1.6) * fan * fall * strength;
	a = floor(a * 40.0 + bayer4(px)) / 40.0;
	COLOR = vec4(s2l(vec3(0.62, 0.68, 1.0)) * a * 0.6, 1.0);
}
