// Waterfall strip: per-column falling streaks in art pixels with a foam lip and a churned base.
shader_type canvas_item;
uniform vec2 size;
uniform float period = 9.0;
uniform vec3 c0 : source_color = vec3(0.32, 0.45, 0.66);
uniform vec3 c1 : source_color = vec3(0.62, 0.74, 0.9);
uniform vec3 c2 : source_color = vec3(0.92, 0.96, 1.0);

float hash(float n) { return fract(sin(n * 91.7) * 43758.5453); }

void fragment() {
	vec2 px = floor(UV * size);
	float speed = 4.0 + floor(hash(px.x) * 3.0);
	float y = px.y - TIME * size.y * speed / period * 2.0;
	float len = 5.0 + hash(px.x + 7.0) * 8.0;
	float s = fract(y / len + hash(px.x + 3.0));
	vec3 col = s > 0.6 ? c2 : (s > 0.3 ? c1 : c0);
	float edge = step(px.x, 0.5) + step(size.x - 1.5, px.x);
	col = mix(col, c0 * 0.7, edge * 0.6);
	float lip = step(px.y, 1.5);
	col = mix(col, c2, lip);
	float base = smoothstep(size.y - 7.0, size.y, px.y);
	col = mix(col, c2, base * step(0.4, hash(px.x + floor(TIME * 8.0))));
	COLOR = vec4(col, 1.0);
	NORMAL_MAP = vec3(0.5, 0.35, 0.85);
}
