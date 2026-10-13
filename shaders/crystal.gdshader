shader_type spatial;
render_mode depth_draw_always;
// A Crystalien's crystal (and their spires, kerbs and the shards that grow on everything): clear
// stone you see through. What's behind it shows, bent by each facet and split a little into
// colours at the edges, stained the crystal's colour; inside, planes of fracture catch the light;
// the edges of the facets run bright, and a slow glow moves through it. It takes the same
// settings the liquid metal does (the runner sets them on whatever it's made of): only the colour
// (horizon), agitation and splash mean anything to a crystal.

uniform vec3 horizon : source_color = vec3(0.7, 0.35, 1.0);
uniform vec3 sky_top : source_color = vec3(0.1, 0.05, 0.2);
uniform vec3 ground : source_color = vec3(0.03, 0.02, 0.06);
uniform vec3 grid_glow : source_color = vec3(0.6, 0.3, 1.0);
uniform float agitation : hint_range(0.0, 1.0) = 0.0;
uniform float real_reflection = 0.0;
uniform float ripple = 1.0;
uniform float collapse = 0.0;
uniform vec3 collapse_center = vec3(0.0);
uniform float ball_radius = 0.2;
uniform float splash = 0.0;
uniform float splash_strength = 0.035;
uniform bool splash_up = false;
// How much shows through it (0: solid coloured stone, 1: glass)
uniform float clarity : hint_range(0.0, 1.0) = 0.62;
uniform sampler2D behind : hint_screen_texture, repeat_disable, filter_linear;

varying vec3 inside;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	inside = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float facing = clamp(dot(n, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, 3.0);
	// Through it: bent by the facet, red, green and blue each a little differently
	vec2 bend = n.xy * (0.035 + 0.05 * (1.0 - facing));
	vec3 through = vec3(
		texture(behind, SCREEN_UV + bend * 1.25).r,
		texture(behind, SCREEN_UV + bend).g,
		texture(behind, SCREEN_UV + bend * 0.75).b);
	// Planes of fracture inside: slabs across the stone at three angles, each catching the light
	// or not as the eye moves
	float flaw = 0.0;
	for (int k = 0; k < 3; k++) {
		vec3 across = normalize(vec3(0.6 + float(k) * 0.9, 1.0 - float(k) * 0.7, 0.4 + float(k) * 0.5));
		float slab = floor(dot(inside, across) * 5.0 + float(k) * 3.1);
		float catches = hash(vec3(slab, float(k), 1.0));
		flaw += pow(catches, 4.0) * pow(abs(dot(n, across)), 2.0);
	}
	float facet = 0.5 + 0.5 * dot(n, normalize(vec3(0.35, 0.8, 0.45)));
	float pulse = 0.85 + 0.15 * sin(TIME * 2.3 + NODE_POSITION_WORLD.x + NODE_POSITION_WORLD.z + inside.y * 2.0);
	vec3 stained = through * mix(vec3(1.0), horizon * 1.4, 0.6);
	vec3 stone = mix(sky_top, horizon, facet) * (0.25 + 0.45 * facet);
	vec3 body = mix(stone, stained + horizon * 0.06, clarity * (1.0 - rim * 0.8));
	ALBEDO = horizon * 0.06;
	EMISSION = body * pulse
		+ horizon * (flaw * 0.55 + rim * 1.3 + agitation * 0.45 + splash * 0.6)
		+ vec3(1.0) * (rim * rim * 0.5 + flaw * flaw * 0.25);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 1.0;
}
