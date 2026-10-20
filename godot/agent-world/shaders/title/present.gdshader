// Shows the linear HDR title viewport in the sRGB root viewport the way Movie Maker captured T704 (8-bit linear, sRGB, truncated).
shader_type canvas_item;
void fragment() {
	vec3 c = floor(clamp(texture(TEXTURE, UV).rgb, 0.0, 1.0) * 255.0) / 255.0;
	vec3 s = mix(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, c * 12.92, vec3(lessThan(c, vec3(0.0031308))));
	COLOR = vec4((floor(s * 255.0) + 0.25) / 255.0, 1.0);
}
