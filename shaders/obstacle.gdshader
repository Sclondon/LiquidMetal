shader_type spatial;
// Obstacles: dark glossy blocks with a glowing outline, coloured by what you do about them
// (orange = jump, cyan = duck, magenta = dodge). The outline comes from the box's UVs.

uniform vec3 body_color : source_color = vec3(0.06, 0.06, 0.08);
uniform vec3 edge_color : source_color = vec3(1.0, 0.5, 0.1);
uniform float edge_width = 0.06;

void fragment() {
	vec2 uv = fract(UV * vec2(3.0, 2.0)); // BoxMesh packs 6 faces into a 3x2 atlas
	vec2 e = min(uv, 1.0 - uv);
	float edge = 1.0 - smoothstep(edge_width * 0.5, edge_width, min(e.x, e.y));
	ALBEDO = body_color;
	METALLIC = 0.3;
	ROUGHNESS = 0.25;
	EMISSION = edge_color * (edge * 2.2 + 0.08);
}
