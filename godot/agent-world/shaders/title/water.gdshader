// Lake: mirrored screen reflection with pixel ripples, horizontal swell bands and a moon glitter path.
shader_type canvas_item;
#include "res://shaders/title/common.gdshaderinc"
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec2 base = vec2(640.0, 360.0);
uniform float horizon = 214.0;
uniform float moon_x = 452.0;

void fragment() {
	vec2 sp = floor(SCREEN_UV * base);
	float dy = sp.y - horizon + 1.0;
	float ph = loop_phase * TAU_;
	float amp = 0.4 + dy * 0.05;
	float off = round(amp * sin(dy * 0.75 - ph * 5.0 + sp.x * 0.015) + amp * 0.6 * sin(sp.x * 0.09 + dy * 0.3 + ph * 3.0) * step(0.5, fract(dy * 0.5)));
	vec2 src = vec2(sp.x + off, horizon - dy - 1.0 + round(sin(sp.x * 0.05 + ph * 2.0) * min(dy * 0.03, 1.0)));
	vec3 refl = pow(texture(screen_tex, (src + 0.5) / base).rgb, vec3(1.0 / 2.2));
	float fres = clamp(dy / 80.0, 0.0, 1.0);
	vec3 deep = vec3(10., 14., 40.) / 255.;
	vec3 col = mix(refl * vec3(0.62, 0.66, 0.92), deep, 0.25 + fres * 0.45);
	// swell bands
	float sw = vnoise(vec2(sp.x * 0.04 + 2.0 * sin(ph), dy * 0.55 + 2.0 * cos(ph)));
	col += vec3(0.07, 0.08, 0.16) * step(0.72, sw) * (1.0 - fres * 0.5);
	// moon glitter path, widening toward the viewer
	float w = 3.0 + dy * 0.35;
	float gx = abs(sp.x - moon_x - sin(dy * 0.4 + ph) * 1.5);
	float lane = 1.0 - smoothstep(w * 0.4, w, gx);
	float flick = hash12(vec2(floor(sp.x / 2.0), dy + floor(fract(loop_phase * 4.0) * 12.0) * 31.0));
	float g = lane * step(0.78 - lane * 0.1, flick);
	col += vec3(0.75, 0.82, 1.0) * g * (1.0 - fres * 0.5);
	col += vec3(0.1, 0.12, 0.22) * lane * 0.6;
	// shoreline foam line at the horizon
	col += vec3(0.25, 0.25, 0.4) * step(dy, 1.0);
	COLOR = vec4(s2l(posterize(col, sp, 30.0)), 1.0);
}
