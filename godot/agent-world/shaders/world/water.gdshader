// Pond and streams in world space: flow streaks, ripples, shore foam, mirrored screen reflection under any camera.
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec2 art = vec2(640.0, 360.0);
uniform float waterline = 127.0;
uniform vec3 ambient = vec3(0.23, 0.26, 0.48);
uniform vec3 deep : source_color = vec3(0.04, 0.07, 0.16);
uniform vec3 shallow : source_color = vec3(0.12, 0.3, 0.38);
uniform vec3 foam : source_color = vec3(0.75, 0.85, 1.0);
uniform float period = 9.0;
uniform float cliff = 26.0;
uniform vec2 moon = vec2(598.0, 176.0);
uniform float moon_on = 1.0;
uniform float day = 0.0;
uniform vec3 day_edge : source_color = vec3(0.44, 0.7, 0.62);
uniform vec3 day_shallow : source_color = vec3(0.26, 0.6, 0.64);
uniform vec3 day_mid : source_color = vec3(0.16, 0.48, 0.58);
uniform vec3 day_deep : source_color = vec3(0.1, 0.38, 0.52);
uniform vec3 day_sky : source_color = vec3(0.56, 0.8, 0.88);
uniform vec3 day_cloud : source_color = vec3(0.78, 0.92, 0.94);
// Baked reflection of the shore trees (art px rect x, y, w, h); w = 0 when the world has none.
uniform sampler2D mirror_tex : filter_nearest;
uniform vec4 mirror_rect = vec4(0.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float bayer4(vec2 p) {
	int i = int(mod(p.x, 4.0)) + int(mod(p.y, 4.0)) * 4;
	const float b[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (b[i] + 0.5) / 16.0;
}

// Hard-edged cloud reflection: flat 2 px rows of short horizontal streaks, no soft falloff.
float cloud_body(vec2 px, float t) {
	float row = floor(px.y / 2.0);
	float cl = sin(px.x * 0.031 + row * 0.41 + t) * 0.55 + sin(px.x * 0.067 - row * 0.23 - t) * 0.35
		+ sin(row * 0.29 + px.x * 0.007 + 2.0 * t) * 0.45;
	return step(0.95, cl);
}

// Day lake: stepped depth (shore band, shallow, mid, deep from `open` = wide mask taps in water, 0..16), sky, drifting cloud reflections, ripple dashes, sun glints.
vec3 day_water(float open, vec2 px, float shore, float t, float rip) {
	float depth = shore * 0.45 + open / 16.0 * 0.55;
	float dz = depth + (bayer4(px) - 0.5) * 0.12;
	vec3 col = day_edge;
	col = mix(col, day_shallow, step(0.2, dz));
	col = mix(col, day_mid, step(0.55, dz));
	col = mix(col, day_deep, step(0.85, dz));
	float open_sky = smoothstep(0.3, 0.8, depth);
	col = mix(col, day_sky, 0.18 * open_sky);
	col = mix(col, day_cloud, cloud_body(px, t) * step(0.45, depth) * 0.32);
	col = mix(col, vec3(1.0), cloud_body(px, t) * (1.0 - cloud_body(px - vec2(0.0, 2.0), t)) * step(0.45, depth) * 0.22);
	float lane = floor(px.y / 3.0);
	float dash = step(0.86, fract(px.x / (14.0 + 9.0 * hash(vec2(lane, 1.0))) + hash(vec2(lane, 2.0)) + t / 6.2831853));
	col = mix(col, day_cloud, dash * step(0.5, fract(px.y / 3.0)) * step(0.3, depth) * 0.4);
	float g = step(0.993, hash(vec2(floor(px.x / 2.0), px.y) + floor(t * 3.0 / 6.2831853) * 17.0)) * step(0.4, depth);
	return col + vec3(1.0, 0.98, 0.9) * g * 0.6;
}

void fragment() {
	vec2 here = UV * art;
	float spp = max(abs(dFdx(here.x)), 1e-4);
	vec4 d = texture(TEXTURE, UV);
	if (d.a < 0.5) { discard; }
	vec2 px = floor(UV * art);
	vec2 flow = d.rg * 2.0 - 1.0;
	float moving = step(0.2, length(flow));
	float shore = d.b;
	float w = 6.2831853 / period;
	float t = TIME * w;
	float rip = sin(px.y * 0.85 + t * 3.0 + sin(px.x * 0.13 + t) * 2.2) * (1.0 - moving);
	float ofs = floor(rip * 1.2 + 0.5);
	vec3 col = mix(mix(shallow, day_shallow, day), mix(deep, day_deep, day), smoothstep(0.0, 0.8, shore));
	// flow streaks: dashes travelling along the stream direction, looped with the period
	vec2 across = vec2(-flow.y, flow.x);
	float lane = floor(dot(px, across) * 0.5);
	float along = dot(px, flow) - (TIME / period) * 36.0;
	float len = hash(vec2(lane, 3.0)) > 0.5 ? 12.0 : 18.0;
	float streak = step(0.8, fract(along / len + hash(vec2(lane, 7.0))));
	col = mix(col, foam * 0.6, streak * moving * 0.55);
	// reflection: the cliff face band mirrored from the screen, then night sky with stars and the moon
	float below = px.y - waterline;
	float k = (1.0 - moving) * (1.0 - smoothstep(cliff * 0.7, cliff, below));
	float ry = 2.0 * waterline - px.y - 1.0;
	vec3 sky = mix(vec3(0.03, 0.05, 0.13), vec3(0.08, 0.1, 0.24), smoothstep(0.0, 90.0, below));
	float star = step(0.993, hash(floor(vec2(px.x + ofs, px.y)))) * (0.6 + 0.4 * sin(t * 4.0 + hash(px) * 6.28));
	sky += vec3(0.75, 0.82, 1.0) * star * 0.7;
	float row = px.y - moon.y;
	float halfw = (6.0 - abs(row) * 0.32) * (0.55 + 0.45 * hash(vec2(row, floor(t * 1.5 / 6.2831853 * 6.0))));
	float shift = floor(sin(row * 0.9 + t * 3.0) * 1.5 + 0.5);
	float mrow = step(0.5, fract(row / 3.0)) * step(abs(row), 16.0);
	sky += vec3(0.7, 0.82, 1.0) * mrow * step(abs(px.x - moon.x - shift), halfw) * 0.75 * moon_on;
	col = mix(col, sky, (1.0 - moving) * smoothstep(0.0, 0.6, shore) * 0.85 * (1.0 - day));
	if (day > 0.5 && moving < 0.5) {
		float open = 0.0;
		for (int i = 0; i < 8; i++) {
			vec2 o = vec2(cos(float(i) * 0.785398), sin(float(i) * 0.785398) * 0.8) / art;
			open += step(0.5, texture(TEXTURE, UV + o * 26.0).a) + step(0.5, texture(TEXTURE, UV + o * 56.0).a);
		}
		col = day_water(open, px, shore, t, rip);
	}
	if (ry > 1.0 && k > 0.0) {
		vec3 r = texture(screen_tex, SCREEN_UV + (vec2(px.x + ofs, ry) + 0.5 - here) / spp * SCREEN_PIXEL_SIZE).rgb;
		col = mix(col, mix(r / ambient * 0.6, r / ambient * 0.75 * day_shallow / max(day_shallow.g, 0.01), day), k * mix(0.85, 0.55, day));
	}
	vec2 mp = vec2(px.x + ofs, px.y) - mirror_rect.xy;
	if (mirror_rect.z > 0.0 && moving < 0.5 && all(greaterThanEqual(mp, vec2(0.0))) && all(lessThan(mp, mirror_rect.zw))) {
		vec4 mr = texture(mirror_tex, (mp + 0.5) / mirror_rect.zw);
		float crest = 1.0 - 0.3 * step(0.6, rip);
		col = mix(col, mr.rgb * mix(vec3(0.6, 0.68, 0.8), vec3(0.7), day) * crest, mr.a * 0.85);
	}
	// sparse moon glints on ripple crests
	float g = step(0.985, hash(vec2(floor(px.x / 2.0), px.y) + floor(TIME * 6.0) * 0.0) ) * step(0.75, rip) * (1.0 - day);
	col += foam * g * 0.8;
	// shore foam line
	float sf = step(shore, 0.12) * step(0.4, sin(px.x * 0.7 + px.y * 0.5 + t * 2.0) * 0.5 + 0.5);
	col = mix(col, foam * 0.75, sf * 0.7);
	COLOR = vec4(col, 1.0);
	float nx = (1.0 - moving) * (1.0 - day) * cos(px.y * 0.85 + t * 3.0) * 0.35;
	NORMAL_MAP = normalize(vec3(nx * 0.4, nx, 1.0)) * 0.5 + 0.5;
}
