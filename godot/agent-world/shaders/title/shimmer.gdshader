// Logo light sweep: a diagonal band crosses the gold letters (HDR, feeds the glow).
shader_type canvas_item;
uniform sampler2D mask : filter_nearest;
uniform float sweep = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float m = texture(mask, UV).a;
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
	float x = (px.x + px.y * 0.6) * TEXTURE_PIXEL_SIZE.x;
	float pos = mix(-0.3, 1.5, smoothstep(0.0, 0.45, sweep));
	float b = 1.0 - smoothstep(0.0, 0.05, abs(x - pos));
	float b2 = 1.0 - smoothstep(0.0, 0.015, abs(x - pos - 0.07));
	c.rgb += m * (b * vec3(0.9, 0.75, 0.45) + b2 * vec3(1.2));
	COLOR = c * COLOR;
}
