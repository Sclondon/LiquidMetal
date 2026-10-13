shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// What moves in the sky over the Crystaliens' moon, drawn on a great ball round the camera and
// added over the sky (which is painted once and never changes: sky.gdshader):
//   - a few stars that flare and gutter
//   - comets, slow, with long tails, and shooting stars, quick
//   - now and then a supernova: a star flares white, throws off a ring, and fades over ten seconds
//   - and things nobody can explain: a six-sided figure of light that turns slowly in the sky and
//     fades again, curtains of light in every colour low round the horizon, and motes of crystal
//     drifting high up
// showcase = 1 holds a comet, a supernova and the figure where they can be seen (for pictures).

uniform vec3 tint : source_color = vec3(0.6, 0.35, 1.0);
uniform float amount = 1.0;
uniform float showcase = 0.0;

varying vec3 dir;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

vec3 any_dir(float seed) {
	float z = hash(seed) * 2.0 - 1.0;
	float a = hash(seed + 5.0) * 6.2832;
	float r = sqrt(max(1.0 - z * z, 0.0));
	return vec3(r * cos(a), z, r * sin(a));
}

vec3 rainbow(float t) {
	return 0.5 + 0.5 * cos(6.2832 * (t + vec3(0.0, 0.33, 0.67)));
}

// Something crossing the sky along a great circle: `turn` of the way round in `seconds`, a new
// one (from somewhere else, going another way) every `every` seconds. Head and tail.
vec3 streak(vec3 d, float every, float seconds, float turn, float width, float tail, float seed) {
	float slot = floor(TIME / every + seed);
	float t = (fract(TIME / every + seed) * every) / seconds; // 0..1 while it's crossing
	if (showcase > 0.5 && seed < 1.0) {
		slot = 3.0;
		t = 0.55;
	}
	if (t > 1.0) {
		return vec3(0.0);
	}
	vec3 axis = any_dir(slot * 7.3 + seed * 31.0 + 1.37);
	// (kept above the horizon: its path's pole is tipped toward the horizon, so it arcs overhead)
	axis = normalize(vec3(axis.x, axis.y * 0.35, axis.z) + vec3(0.02, 0.0, 0.03));
	vec3 start = normalize(cross(axis, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 0.0));
	vec3 side = cross(axis, start);
	float along = atan(dot(d, side), dot(d, start)); // where round the circle this bit of sky is
	float head = (t - 0.5) * turn + 1.5708; // (overhead halfway through)
	float behind = head - along;
	behind = behind - 6.2832 * floor((behind + 3.1416) / 6.2832);
	float off = dot(d, axis);
	float fade = smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.8, 1.0, t));
	float glow = exp(-(behind * behind + off * off) / (width * width));
	float back = max(behind, 0.0); // (only behind the head: ahead of it there's nothing)
	float spread = width + back * 0.07;
	float streaming = step(0.0, behind) * exp(-back / tail) * exp(-off * off / (spread * spread));
	vec3 ice = mix(vec3(0.7, 0.9, 1.0), tint, 0.35);
	return (vec3(1.0) * glow * 2.5 + ice * streaming * 0.9) * fade;
}

// A star dying: white, then a ring thrown outward through orange to the sky's colour
vec3 supernova(vec3 d) {
	float every = 46.0;
	float slot = floor(TIME / every);
	float t = fract(TIME / every) * every / 10.0; // 0..1 over its ten seconds
	if (showcase > 0.5) {
		slot = 5.0;
		t = 0.32;
	}
	if (t > 1.0 || (hash(slot + 9.0) < 0.3 && showcase < 0.5)) {
		return vec3(0.0); // (not every time)
	}
	vec3 at = any_dir(slot * 3.7 + 2.0);
	at = normalize(vec3(at.x, abs(at.y) * 0.7 + 0.25, at.z));
	float away = acos(clamp(dot(d, at), -1.0, 1.0));
	float flash = exp(-t * 9.0);
	float core = exp(-away * away / (0.00004 + flash * 0.0012)) * (0.5 + flash * 6.0) * (1.0 - smoothstep(0.6, 1.0, t));
	// Four thin rays through it while it's brightest
	vec3 e1 = normalize(cross(at, vec3(0.3, 1.0, 0.2)));
	vec3 e2 = cross(at, e1);
	vec2 p = vec2(dot(d, e1), dot(d, e2));
	float rays = (exp(-abs(p.x) * 600.0) + exp(-abs(p.y) * 600.0)) * exp(-away * 22.0) * flash * 3.0;
	float reach = 0.012 + t * 0.11;
	float from_shell = (away - reach) / (0.004 + t * 0.012);
	float shell = exp(-from_shell * from_shell) * (1.0 - t) * (0.5 + 0.5 * hash3(floor(d * 90.0)));
	vec3 ember = mix(vec3(1.0, 0.75, 0.4), tint, smoothstep(0.1, 0.7, t));
	return vec3(1.0) * (core + rays) + ember * shell * 1.6;
}

// The figure: a hexagon with a triangle in it, drawn in light, turning, there for a while
vec3 figure(vec3 d) {
	float every = 70.0;
	float slot = floor(TIME / every + 0.4);
	float t = fract(TIME / every + 0.4) * every / 24.0;
	if (showcase > 0.5) {
		slot = 2.0;
		t = 0.5;
	}
	if (t > 1.0) {
		return vec3(0.0);
	}
	vec3 at = any_dir(slot * 5.1 + 40.0);
	at = normalize(vec3(at.x, abs(at.y) * 0.6 + 0.35, at.z));
	if (dot(d, at) < 0.9) {
		return vec3(0.0);
	}
	vec3 e1 = normalize(cross(at, vec3(0.2, 1.0, 0.3)));
	vec3 e2 = cross(at, e1);
	float spin = TIME * 0.07;
	vec2 p = vec2(dot(d, e1), dot(d, e2)) / 0.13;
	p = vec2(p.x * cos(spin) - p.y * sin(spin), p.x * sin(spin) + p.y * cos(spin));
	// Distance to a hexagon's edge, and to a triangle's inside it turning the other way
	float a = atan(p.y, p.x);
	float r = length(p);
	float hex = abs(r * cos(mod(a, 1.0472) - 0.5236) - 0.8);
	float a2 = a + spin * 3.0;
	float tri = abs(r * cos(mod(a2, 2.0944) - 1.0472) - 0.3);
	float spokes = abs(sin(a * 3.0)) * r; // three lines through the middle
	float lines = exp(-hex * 70.0) + exp(-tri * 90.0) * 0.8 + exp(-spokes * 60.0) * step(r, 0.8) * 0.35;
	float shimmer = 0.6 + 0.4 * sin(TIME * 5.0 + r * 30.0);
	float fade = smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.75, 1.0, t));
	return mix(tint, vec3(1.0), 0.5) * lines * shimmer * fade * 0.9 + rainbow(a / 6.2832 + TIME * 0.05) * exp(-hex * 12.0) * fade * 0.12;
}

void vertex() {
	dir = VERTEX;
}

void fragment() {
	vec3 d = normalize(dir);
	vec3 col = vec3(0.0);

	// Stars that flare: a sparse few, each on its own slow beat, with a cross of light at the peak
	vec3 g = d * 9.0;
	vec3 id = floor(g);
	if (hash3(id + 3.0) > 0.9) {
		vec3 where = vec3(hash3(id + 1.0), hash3(id + 2.0), hash3(id + 4.0)) - 0.5;
		vec3 to = fract(g) - 0.5 - where * 0.6;
		float beat = pow(0.5 + 0.5 * sin(TIME * (0.6 + hash3(id) * 1.6) + hash3(id + 8.0) * 6.2832), 6.0);
		float cross_light = exp(-min(abs(to.x) + abs(to.y) * 0.02, abs(to.y) + abs(to.x) * 0.02) * 90.0) * exp(-length(to) * 14.0);
		col += vec3(0.9, 0.95, 1.0) * (exp(-dot(to, to) * 2500.0) * 2.0 + cross_light * 1.2) * beat;
	}

	// Comets (slow, long tails) and shooting stars (quick)
	col += streak(d, 38.0, 26.0, 1.6, 0.012, 0.28, 0.0);
	col += streak(d, 61.0, 34.0, 1.3, 0.016, 0.4, 3.3);
	col += streak(d, 7.0, 0.9, 0.5, 0.004, 0.05, 11.7);
	col += streak(d, 11.0, 0.7, 0.4, 0.003, 0.04, 23.1);

	col += supernova(d);
	col += figure(d);

	// Curtains of light low round the horizon, every colour, breathing
	float az = atan(d.x, d.z);
	float fold = sin(az * 7.0 + TIME * 0.11 + sin(az * 3.0 - TIME * 0.07) * 2.0);
	float hem = 0.1 + 0.07 * fold;
	float curtain = smoothstep(0.02, hem, d.y) * (1.0 - smoothstep(hem, hem + 0.22, d.y));
	float strands = 0.5 + 0.5 * sin(az * 140.0 + fold * 5.0 + TIME * 0.6);
	float breath = 0.45 + 0.55 * sin(TIME * 0.13 + az * 1.5);
	col += rainbow(az / 6.2832 * 2.0 + TIME * 0.015 + d.y * 1.5) * curtain * (0.35 + 0.65 * strands) * max(breath, 0.0) * 0.22;

	// Motes of crystal drifting high up: glints that come and go
	vec3 m = d * 34.0 + vec3(TIME * 0.05, -TIME * 0.11, TIME * 0.03);
	vec3 mote_id = floor(m);
	float mote = step(0.965, hash3(mote_id)) * (1.0 - smoothstep(0.0, 0.25, length(fract(m) - 0.5)));
	mote *= pow(0.5 + 0.5 * sin(TIME * 3.0 + hash3(mote_id + 2.0) * 6.2832), 4.0) * smoothstep(0.25, 0.6, d.y);
	col += rainbow(hash3(mote_id + 5.0)) * mote * 0.9;

	ALBEDO = col * amount;
}
