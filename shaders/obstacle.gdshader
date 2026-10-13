shader_type spatial;
// Cut crystal: what the Crystaliens build everything from (the colosseum's wall, the stones in
// the arena, the things to jump, duck and dodge on the ring road). Smoky, half clear: you make out
// what's behind it, bent and stained its colour. Each face is cut into big angled facets, every
// one its own shade and bending the view its own way; the cut edges of the block catch the light,
// and a slow glow moves through the stone. Still coloured by what you do about it (amber: jump,
// pale blue: duck, rose: dodge). The edges come from the box's UVs; the facets are in world
// metres, so they run on from block to block. (edge_color: the crystal's colour.)

uniform vec3 edge_color : source_color = vec3(1.0, 0.5, 0.1);
uniform float edge_pixels = 2.5;
uniform float grid_size = 1.0; // (how big the facets are: this times 1.8 m)
uniform float glow = 1.0;
// How much shows through it (less than a shard: these are things to see coming)
uniform float clarity : hint_range(0.0, 1.0) = 0.42;
uniform sampler2D behind : hint_screen_texture, repeat_disable, filter_linear;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// The block's own cut edges
	vec2 uv = fract(UV * vec2(3.0, 2.0));
	vec2 to_edge = min(uv, 1.0 - uv) / max(fwidth(uv), vec2(1e-5));
	float edge = 1.0 - smoothstep(edge_pixels * 0.4, edge_pixels, min(to_edge.x, to_edge.y));

	// Facets: slanted triangles across the plane of the face
	vec3 n = abs(world_normal);
	vec2 plane = n.x > 0.5 ? world_pos.zy : (n.y > 0.5 ? world_pos.xz : world_pos.xy);
	vec2 q = plane / (grid_size * 1.8);
	q.x += q.y * 0.55;
	vec2 cell = floor(q);
	vec2 f = fract(q);
	float half_cell = step(1.0, f.x + f.y);
	float shade = hash(cell + half_cell * 7.3);
	// (the seams between facets: a hair of light)
	float seam = 1.0 - smoothstep(0.0, 0.035, min(min(f.x, f.y), abs(f.x + f.y - 1.0)));

	// Through it: each facet tilts the view its own way
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec2 tilt = (vec2(hash(cell + half_cell * 3.1), hash(cell + half_cell * 5.7 + 9.0)) - 0.5) * 0.09;
	vec2 bend = NORMAL.xy * 0.03 + tilt;
	vec3 through = vec3(texture(behind, SCREEN_UV + bend * 1.2).r, texture(behind, SCREEN_UV + bend).g, texture(behind, SCREEN_UV + bend * 0.8).b);

	float face = 0.5 + 0.5 * dot(world_normal, normalize(vec3(0.35, 0.8, 0.45)));
	float rim = pow(1.0 - facing, 3.0);
	float pulse = 0.5 + 0.5 * sin(world_pos.y * 0.9 - TIME * 0.7 + shade * 6.2832);
	vec3 stone = edge_color * (0.1 + 0.34 * shade * face);
	vec3 stained = through * mix(vec3(1.0), edge_color * 1.3, 0.7) * (0.75 + 0.25 * shade);
	ALBEDO = edge_color * 0.05;
	METALLIC = 0.0;
	ROUGHNESS = 0.06;
	SPECULAR = 1.0;
	EMISSION = mix(stone * glow * 1.6, stained + stone * 0.5, clarity * (1.0 - rim * 0.7))
		+ edge_color * glow * (seam * 0.14 + pulse * 0.06 + rim * 0.8)
		+ mix(edge_color, vec3(1.0), 0.5) * edge * 0.6 * glow;
}
