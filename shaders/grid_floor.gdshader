shader_type spatial;
// Dark polished floor with a glowing grid: fine lines every metre-ish, bright ones every 20 m.

uniform vec3 base_color : source_color = vec3(0.035, 0.04, 0.055);
uniform vec3 line_color : source_color = vec3(0.15, 0.45, 1.0);
uniform float cell = 4.0;
uniform float major_cell = 20.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid(vec2 p, float size, float width) {
	vec2 g = p / size;
	vec2 d = abs(fract(g - 0.5) - 0.5) / (fwidth(g) * width);
	return 1.0 - min(min(d.x, d.y), 1.0);
}

void fragment() {
	float minor = grid(world_pos.xz, cell, 1.0);
	float major = grid(world_pos.xz, major_cell, 2.0);
	ALBEDO = base_color;
	METALLIC = 0.5;
	ROUGHNESS = 0.3;
	EMISSION = line_color * (minor * 0.25 + major * 0.9);
}
