shader_type spatial;
// The floor: dark brushed-metal plates, a plate to each grid cell, set in glowing seams (fine ones
// every cell, bright ones every major cell). Each plate is a slightly different shade and sheen,
// with grain and scuffs breaking up its surface, and it's mostly rough: it gives the light back
// as a soft sheen and lets the neon lines and the sky's colours do the work, not a wide glare.
// Drawn in world space, so a floor that moves along with the runner doesn't slide.

uniform vec3 base_color : source_color = vec3(0.035, 0.04, 0.055);
uniform vec3 line_color : source_color = vec3(0.15, 0.45, 1.0);
uniform float cell = 4.0;
uniform float major_cell = 20.0;
uniform float roughness_low = 0.42; // the smoothest plates...
uniform float roughness_high = 0.78; // ...and the roughest

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		total += noise(p) * amp;
		p = p * 2.03 + vec2(17.0, 9.0);
		amp *= 0.5;
	}
	return total;
}

// 1 on a grid line of the given size (antialiased; width in pixels)
float grid(vec2 p, float size, float width) {
	vec2 g = p / size;
	vec2 d = abs(fract(g - 0.5) - 0.5) / (fwidth(g) * width);
	return 1.0 - min(min(d.x, d.y), 1.0);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 tile = floor(p / cell);
	vec2 in_tile = fract(p / cell); // 0..1 across the plate
	float tile_rand = hash(tile);
	// The plate's own shade and sheen
	float shade = mix(0.75, 1.2, tile_rand);
	// Brushed: grain stretched along the plate (each plate brushed one way or the other)
	vec2 brush_p = tile_rand > 0.5 ? p.xy * vec2(1.0, 18.0) : p.xy * vec2(18.0, 1.0);
	float brush = noise(brush_p * 3.0);
	float scuffs = fbm(p * 0.35 + tile * 3.1);
	float grime = smoothstep(0.45, 0.8, fbm(p * 0.08));
	// The bevel round the plate's edge: a dark groove the seam's light sits in
	vec2 edge = min(in_tile, 1.0 - in_tile) * cell; // metres to the plate's nearest edge
	float to_edge = min(edge.x, edge.y);
	float groove = 1.0 - smoothstep(0.02, 0.09, to_edge);
	// The lines, faded out into the distance so the fine ones don't shimmer
	float dist = length(world_pos - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	float fade = 1.0 - smoothstep(25.0, 90.0, dist);
	float minor = grid(p, cell, 1.2) * fade;
	float major = grid(p, major_cell, 2.2);
	float halo = (1.0 - smoothstep(0.0, 0.35, to_edge)) * 0.06 * fade; // a little of the seam's light on the plate

	vec3 color = base_color * shade * mix(0.85, 1.15, brush) * mix(1.0, 0.7, grime);
	ALBEDO = color * (1.0 - groove * 0.6);
	METALLIC = 0.35;
	SPECULAR = 0.35;
	ROUGHNESS = clamp(mix(roughness_low, roughness_high, tile_rand) + (scuffs - 0.5) * 0.25 + brush * 0.06 + grime * 0.15 + groove * 0.2, 0.2, 1.0);
	// The plate's surface: a gentle tilt from its grain, and the bevel rolling down into the seam
	vec2 bevel_dir = vec2(in_tile.x < 0.5 ? -1.0 : 1.0, in_tile.y < 0.5 ? -1.0 : 1.0);
	vec2 bevel = (edge.x < edge.y ? vec2(bevel_dir.x, 0.0) : vec2(0.0, bevel_dir.y)) * groove * 0.5;
	vec2 tilt = vec2(noise(p * 0.9) - 0.5, noise(p * 0.9 + 31.0) - 0.5) * 0.06 + bevel;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(tilt.x, 1.0, tilt.y)), 0.0)).xyz);
	EMISSION = line_color * (minor * 0.3 + major * 0.95 + halo);
}
