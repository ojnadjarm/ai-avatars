// Selected menu text: one bright sweep after selection; sweep < 0 = off.
shader_type canvas_item;
uniform float sweep = -1.0;
void fragment() {
	vec4 c = COLOR;
	if (sweep >= 0.0) {
		float x = UV.x;
		float b = 1.0 - smoothstep(0.0, 0.08, abs(x - mix(-0.2, 1.2, sweep)));
		c.rgb += vec3(1.4, 1.2, 0.8) * b * c.a;
	}
	COLOR = c;
}
