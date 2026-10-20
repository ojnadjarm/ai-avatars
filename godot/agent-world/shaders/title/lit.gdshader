// Night-lit layer: base shows the albedo darkened to moonlight; Light2D adds on the full albedo so warm pools read.
shader_type canvas_item;
uniform vec3 dark = vec3(0.5, 0.5, 0.6);
uniform vec3 moon_dir = vec3(0.55, 0.45, 0.7);
uniform vec3 moon_col = vec3(0.16, 0.2, 0.42);
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(c.rgb * dark + c.rgb * moon_col * max(dot(NORMAL, normalize(moon_dir)) - 0.55, 0.0) * 2.2, c.a);
}
void light() {
	vec3 a = texture(TEXTURE, UV).rgb;
	float nl = clamp(dot(NORMAL, LIGHT_DIRECTION) * 0.7 + 0.3, 0.0, 1.0);
	LIGHT = vec4(a * LIGHT_COLOR.rgb * LIGHT_ENERGY * nl, LIGHT_COLOR.a);
}
