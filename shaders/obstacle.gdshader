shader_type spatial;
render_mode depth_draw_always;
// Grown crystal: what the Crystaliens build everything from (the colosseum's wall, the stones in
// the arena, the things to jump, duck and dodge on the ring road). Smoky, half clear: you make out
// what's behind it, bent and stained its colour. Its faces aren't cut to a pattern: they're a
// crowd of irregular facets, the way crystal grows, each tilted its own way (so each bends the
// view and catches the light differently), with bright ridges where facets meet, a second, deeper
// layer of fractures that slides behind the surface as you move, and veins of light that pulse
// slowly through the stone. Still coloured by what you do about it (amber: jump, pale blue: duck,
// rose: dodge). The facets are in world metres, so they run on from block to block.
// (edge_color: the crystal's colour.)

uniform vec3 edge_color : source_color = vec3(1.0, 0.5, 0.1);
uniform float edge_pixels = 2.5; // (unused now: kept so old settings still load)
uniform float grid_size = 1.0; // how big the facets are: about this many metres across
uniform float glow = 1.0;
// How much shows through it (less than a shard: these are things to see coming)
uniform float clarity : hint_range(0.0, 1.0) = 0.42;
uniform sampler2D behind : hint_screen_texture, repeat_disable, filter_linear;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 world_view;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_view = normalize(CAMERA_POSITION_WORLD - world_pos);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

// The facets: which one this point is in (its own random pair), and how near its edge it is
// (0 on the ridge between two facets). Stretched so they're long shards, not round cells.
vec3 facets(vec2 p) {
	p = vec2(p.x * 1.0 + p.y * 0.35, p.y * 0.55);
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float nearest = 8.0;
	float second = 8.0;
	vec2 who = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 h = hash2(cell + g);
			float d = length(g + h - f);
			if (d < nearest) {
				second = nearest;
				nearest = d;
				who = h;
			} else if (d < second) {
				second = d;
			}
		}
	}
	return vec3(who, second - nearest);
}

void fragment() {
	// The plane of this face, in world metres
	vec3 n = abs(world_normal);
	vec2 plane = n.x > 0.5 ? world_pos.zy : (n.y > 0.5 ? world_pos.xz : world_pos.xy);
	vec2 across = n.x > 0.5 ? world_view.zy : (n.y > 0.5 ? world_view.xz : world_view.xy);
	vec3 top = facets(plane / grid_size);
	// A layer of fractures deeper in the stone: it shifts against the surface as the eye moves
	vec3 deep = facets((plane - across * 0.6) / (grid_size * 2.3) + 17.0);

	float ridge = 1.0 - smoothstep(0.0, 0.07, top.z);
	float deep_ridge = 1.0 - smoothstep(0.0, 0.05, deep.z);
	// Each facet is tilted its own way: it bends what's behind it, and catches the light or not
	vec2 tilt = (top.xy - 0.5) * 0.11;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec2 bend = NORMAL.xy * 0.03 + tilt;
	vec3 through = vec3(texture(behind, SCREEN_UV + bend * 1.2).r, texture(behind, SCREEN_UV + bend).g, texture(behind, SCREEN_UV + bend * 0.8).b);
	float catches = pow(clamp(dot(normalize(vec3(tilt * 6.0, 1.0)), normalize(vec3(across * 0.8 + vec2(0.3, 0.5), 1.0))), 0.0, 1.0), 24.0);

	float face = 0.5 + 0.5 * dot(world_normal, normalize(vec3(0.35, 0.8, 0.45)));
	float rim = pow(1.0 - facing, 3.0);
	// Veins of light wandering up through it
	float vein = deep_ridge * (0.5 + 0.5 * sin(world_pos.y * 1.3 + deep.x * 6.2832 - TIME * 0.8));
	vec3 stone = edge_color * (0.08 + 0.3 * top.x * face + 0.12 * deep.y);
	vec3 stained = through * mix(vec3(1.0), edge_color * 1.3, 0.7) * (0.7 + 0.3 * top.y);
	ALBEDO = edge_color * 0.05;
	METALLIC = 0.0;
	ROUGHNESS = 0.06;
	SPECULAR = 1.0;
	EMISSION = mix(stone * glow * 1.6, stained + stone * 0.5, clarity * (1.0 - rim * 0.7))
		+ edge_color * glow * (ridge * 0.22 + vein * 0.5 + rim * 0.8)
		+ mix(edge_color, vec3(1.0), 0.6) * (catches * 0.7 + ridge * rim * 0.5) * glow;
}
