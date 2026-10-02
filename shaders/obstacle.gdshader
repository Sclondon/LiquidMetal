shader_type spatial;
// Tron blocks: glossy black with hard glowing edges, a faint grid of light on every face
// and a band of light scanning up them. Coloured by what you do about them (orange = jump,
// cyan = duck, magenta = dodge). The edges come from the box's UVs and stay a few pixels
// wide at any distance; the grid is in world metres, so it lines up from block to block.

uniform vec3 edge_color : source_color = vec3(1.0, 0.5, 0.1);
uniform float edge_pixels = 2.5;
uniform float grid_size = 1.0; // metres between grid lines

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float lines(vec2 p, float width) {
	vec2 d = abs(fract(p - 0.5) - 0.5) / max(fwidth(p), vec2(1e-5));
	return 1.0 - smoothstep(width * 0.5, width, min(d.x, d.y));
}

void fragment() {
	// The edges: near any side of this face's patch of the BoxMesh's 3x2 UV atlas
	vec2 uv = fract(UV * vec2(3.0, 2.0));
	vec2 to_edge = min(uv, 1.0 - uv) / max(fwidth(uv), vec2(1e-5));
	float edge = 1.0 - smoothstep(edge_pixels * 0.5, edge_pixels, min(to_edge.x, to_edge.y));
	float halo = 1.0 - smoothstep(0.0, edge_pixels * 5.0, min(to_edge.x, to_edge.y));

	// The grid, on the plane of the face
	vec3 n = abs(world_normal);
	vec2 plane = n.x > 0.5 ? world_pos.zy : (n.y > 0.5 ? world_pos.xz : world_pos.xy);
	float grid = lines(plane / grid_size, 1.0);

	// A band of light climbing the block every few seconds
	float band = fract(world_pos.y * 0.25 - TIME * 0.35);
	float scan = smoothstep(0.0, 0.04, band) * (1.0 - smoothstep(0.04, 0.12, band));

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = vec3(0.005, 0.007, 0.012);
	METALLIC = 0.7;
	ROUGHNESS = 0.12;
	EMISSION = edge_color * (edge * 4.0 + halo * 0.35 + grid * 0.22 + scan * 0.5 + fresnel * 0.25 + 0.02);
}
