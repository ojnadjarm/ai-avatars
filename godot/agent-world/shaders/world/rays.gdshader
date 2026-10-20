// Moon shafts through the canopy gap: widening beam, banded rays drifting slowly; additive.
shader_type canvas_item;
render_mode blend_add;
uniform vec2 art = vec2(640.0, 360.0);
uniform vec2 offset = vec2(0.0);
uniform vec2 origin = vec2(176.0, 20.0);
uniform vec2 dir = vec2(0.5, 1.0);
uniform vec3 col : source_color = vec3(0.55, 0.7, 1.0);
uniform float strength = 0.28;
uniform float reach = 250.0;
uniform float period = 9.0;

void fragment() {
	vec2 px = offset + UV * art;
	vec2 d = normalize(dir);
	vec2 rel = px - origin;
	float along = dot(rel, d);
	float across = dot(rel, vec2(d.y, -d.x));
	float spread = 14.0 + along * 0.28;
	float beam = 1.0 - smoothstep(0.35, 1.0, abs(across) / spread);
	float t = TIME * 6.2831853 / period;
	float a = across / spread;
	float rays = 0.55 + 0.45 * sin(a * 9.0 + sin(a * 3.0 + t) * 1.6) * sin(a * 23.0 - t * 2.0 + 1.3);
	float fade = smoothstep(-10.0, 30.0, along) * (1.0 - smoothstep(reach * 0.5, reach, along));
	float pulse = 0.9 + 0.1 * sin(t);
	COLOR = vec4(col * beam * rays * fade * strength * pulse, 1.0);
}
