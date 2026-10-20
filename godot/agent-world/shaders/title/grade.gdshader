// Final grade: vignette, cool shadows, warm highlights.
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	vec2 q = SCREEN_UV - 0.5;
	float v = 1.0 - dot(q * vec2(1.2, 1.3), q * vec2(1.2, 1.3)) * 0.75;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, c * vec3(0.92, 0.95, 1.1), 1.0 - smoothstep(0.0, 0.35, l));
	c = mix(c, c * vec3(1.06, 1.0, 0.94), smoothstep(0.55, 1.0, l));
	COLOR = vec4(c * clamp(v, 0.0, 1.0), 1.0);
}
