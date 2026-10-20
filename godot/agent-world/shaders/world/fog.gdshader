// Ground fog: two noise-texture banks drifting on looping circles, masked by the fog density map, stepped and dithered per art pixel.
shader_type canvas_item;
uniform sampler2D mask : filter_linear;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform vec2 art = vec2(640.0, 360.0);
uniform vec4 tint : source_color = vec4(0.42, 0.52, 0.8, 1.0);
uniform float strength = 0.5;
uniform float period = 9.0;
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
const float STEPS = 6.0;

void fragment() {
	vec2 px = floor(UV * art) + 0.5;
	float t = TIME * 6.2831853 / period;
	vec2 o1 = vec2(cos(t), sin(t)) * 10.0;
	vec2 o2 = vec2(sin(t), -cos(t)) * 16.0;
	float n = texture(noise, (px + o1) / vec2(420.0, 300.0)).r * 0.62 + texture(noise, (px - o2) / vec2(170.0, 130.0) + 0.37).r * 0.38;
	float m = texture(mask, px / art).r;
	float a = smoothstep(0.32, 0.78, n * (0.55 + m)) * m * strength;
	ivec2 b = ivec2(mod(px, 4.0));
	a = floor(a * STEPS + BAYER[b.y * 4 + b.x] / 16.0) / STEPS;
	COLOR = vec4(tint.rgb, a);
}
