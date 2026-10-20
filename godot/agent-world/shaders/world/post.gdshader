// Final grade: cool shadows, warm highlights, vignette.
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = texture(screen_tex, uv).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, c * vec3(0.86, 0.92, 1.18), (1.0 - smoothstep(0.0, 0.35, l)) * 0.5);
	c = mix(c, c * vec3(1.06, 1.0, 0.92), smoothstep(0.55, 1.0, l) * 0.4);
	vec2 v = (uv - vec2(0.5, 0.47)) * vec2(1.0, 1.25);
	c *= 1.0 - smoothstep(0.18, 0.75, dot(v, v) * 1.6) * 0.55;
	COLOR = vec4(c, 1.0);
}
